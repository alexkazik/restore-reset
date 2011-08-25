
#include <avr/io.h>

/*
** REGISTER DEFINITION
*/

// Registers 0..15 are not used, because some AVRs don't have such
#define REG_SREG 16 // to store the SREG in an interrupt
#define REG_KEY_VALID 17 // is the REG_KEY_STATE valid (0) or invalid (!=0)
#define REG_KEY_STATE 18 // the state of the key (on valid if REG_KEY_VALID is 0)
#define REG_TIMER 19 // the timer
// Registers X..29 are just not used
// Registers 30,31 are not used, so they can be used a a stack for those AVR's
//      which don't have SRAM (two bytes are enough)

/*
** I/O DEFINITION - ALL MUST BE ON ONE PORT
*/

#define PORT PORTB
#define PIN PINB
#define DDR DDRB

#define RESTORE_IN_BIT 0
#define RESTORE_OUT_BIT 1
#define RESET_BIT 2
// you can comment the LEDs OUT (one or both) and the code will follow
#define LED1_BIT 3
#define LED2_BIT 4

// do not change this
#ifdef LED1_BIT
	#define LED1_MASK (1<<LED1_BIT)
#else
	#define LED1_MASK 0
#endif
#ifdef LED2_BIT
	#define LED2_MASK (1<<LED2_BIT)
#else
	#define LED2_MASK 0
#endif

/*
** TIMING DEFINITION
*/

#define TIME_BASE 20000 // how many usec until the timer produces an overflow

#define TIME_LINE_LOW (200000/TIME_BASE) // how long should the restore/reset line low
#define TIME_LINE_PAUSE (200000/TIME_BASE) // how long the restore/reset line shouln't be pulled low again
#define TIME_RESET (2000000/TIME_BASE) // how long you should press the restore key to trigger a reset
#define TIME_BLINK_LED (500000/TIME_BASE) // how long should the LED blink

#if TIME_LINE_LOW <= 1 || TIME_LINE_PAUSE <= 1 || TIME_RESET <= 1 || TIME_BLINK_LED <= 1
	#error "times must be >= 2 BASES"
#elif TIME_RESET - (TIME_LINE_LOW + TIME_LINE_PAUSE) <= 1
	#error "time for reset is too low"
#elif TIME_RESET - (TIME_LINE_LOW + TIME_LINE_PAUSE) > 255
	#error "time for reset is too high"
#elif TIME_BLINK_LED - TIME_LINE_LOW <= 1
	#error "time for blink must be larger than for holding the line low"
#endif

/*
** VECTORS (SHORT VERSION)
*/

.section .vectors,"ax",@progbits
.global	__vectors
.func	__vectors
__vectors:
#if defined(__AVR_ATtiny13__) || defined(__AVR_ATtiny13A__)
	rjmp main // vector 0
	nop // vector 1, unused
	nop // vector 2, unused
	rjmp sig_overflow0 // vector 3
#elif defined(__AVR_ATtiny24__) || defined(__AVR_ATtiny24A__) || defined(__AVR_ATtiny44__) || defined(__AVR_ATtiny44A__) || defined(__AVR_ATtiny84__)
	rjmp main // vector 0
	nop // vector 1, unused
	nop // vector 2, unused
	nop // vector 3, unused
	nop // vector 4, unused
	nop // vector 5, unused
	nop // vector 6, unused
	nop // vector 7, unused
	nop // vector 8, unused
	nop // vector 9, unused
	nop // vector 10, unused
	rjmp sig_overflow0 // vector 11
#else
	#error "unknown AVR"
#endif
.endfunc

.section .text

/*
** POWER UP ROUTINE
*/
.global main
.func main
main:

	// REG_TIMER is used as a temp, only in use after releasing the interrupt

	// setup stack
	ldi REG_TIMER, RAMEND & 0xff
	out _SFR_IO_ADDR(SPL), REG_TIMER
	// hi end of the stack, only used for systems with >128 bytes of ram
	#ifdef SPH
		ldi REG_TIMER, RAMEND >> 8
		out _SFR_IO_ADDR(SPH), REG_TIMER
	#endif
	
	// init I/O
	// all switched off lines (REST_OUT/RES/LED*) are input, no pullup -> not connected
	
	ldi REG_TIMER, LED1_MASK | LED2_MASK // the mast is 0 the the LED is not known
	out _SFR_IO_ADDR(DDR), REG_TIMER // LEDs output, others input
	ldi REG_TIMER, (1<<RESTORE_IN_BIT)
	out _SFR_IO_ADDR(PORT), REG_TIMER // pulllup for REST_IN, others without pullup / output low

	// init timer! to the correct TIME_BASE
#if defined(__AVR_ATtiny13__) || defined(__AVR_ATtiny13A__)
	#if TIME_BASE != 20000
		#error "currently only 20ms as base are supported"
	#endif
	// time to overflow 78(.125) * (clock/256) ~= 20ms
	ldi REG_TIMER, 78
	out _SFR_IO_ADDR(OCR0A), REG_TIMER
	// ctc mode (two of the three WGM bits)
	ldi	REG_TIMER, (1<<WGM01) | (1<<WGM00)
	out _SFR_IO_ADDR(TCCR0A), REG_TIMER
	// ctc mode (the last of the three WGM bits)
	// AND scaler: clock/256
	ldi REG_TIMER, (1<<WGM02) | (1<<CS02)
	out _SFR_IO_ADDR(TCCR0B), REG_TIMER
	// enable interrupt
	ldi REG_TIMER, (1<<TOIE0)
	out _SFR_IO_ADDR(TIMSK0), REG_TIMER
#elif defined(__AVR_ATtiny24__) || defined(__AVR_ATtiny24A__) || defined(__AVR_ATtiny44__) || defined(__AVR_ATtiny44A__) || defined(__AVR_ATtiny84__)
	#if TIME_BASE != 20000
		#error "currently only 20ms as base are supported"
	#endif
	// time to overflow 78(.125) * (clock/256) ~= 20ms
	ldi REG_TIMER, 78
	out _SFR_IO_ADDR(OCR0A), REG_TIMER
	// ctc mode (two of the three WGM bits)
	ldi	REG_TIMER, (1<<WGM01) | (1<<WGM00)
	out _SFR_IO_ADDR(TCCR0A), REG_TIMER
	// ctc mode (the last of the three WGM bits)
	// AND scaler: clock/256
	ldi REG_TIMER, (1<<WGM02) | (1<<CS02)
	out _SFR_IO_ADDR(TCCR0B), REG_TIMER
	// enable interrupt
	ldi REG_TIMER, (1<<TOIE0)
	out _SFR_IO_ADDR(TIMSK0), REG_TIMER
#else
	#error "unknown AVR"
#endif

	// prepare launch
	ser REG_KEY_VALID // not valid
	clr REG_KEY_STATE // key pressed
	// set LEDs (1 is already on, 2 will be switched off)
	#ifdef LED2_BIT
		cbi _SFR_IO_ADDR(DDR), LED2_BIT // set to input, port=0 -> n/c
	#endif
	// enable interrup
	sei
	
	// the real program
 
state0: // wait for releasing the restore key
	tst REG_KEY_VALID
	brne state0 // not valid, try again
	tst REG_KEY_STATE
	breq state0 // key still pressed, loop

state1: // wait for pressing the restore key
	tst REG_KEY_VALID
	brne state1 // not valid, try again
	tst REG_KEY_STATE
	brne state1 // key not pressed, loop

	// pull RESTORE_OUT low for TIME_LINE_LOW
	ldi REG_TIMER, TIME_LINE_LOW // init timer
	sbi _SFR_IO_ADDR(DDR), RESTORE_OUT_BIT // set to output, port=0 -> low

state2: // wait for TIME_LINE_LOW
	tst REG_TIMER
	brne state2 // not yet done -> loop

	// restore RESTORE_OUT for (at least) TIME_LINE_PAUSE
	ldi REG_TIMER, TIME_LINE_PAUSE // init timer
	cbi _SFR_IO_ADDR(DDR), RESTORE_OUT_BIT // set to input, port=0 -> n/c
  
state3: // wait for TIME_LINE_PAUSE
	tst REG_TIMER
	brne state3 // not yet done -> loop

	// wait?
	ldi REG_TIMER, TIME_RESET - (TIME_LINE_LOW + TIME_LINE_PAUSE) // init timer

state4: // wait for either key released or time to reset
	tst REG_KEY_VALID
	brne 1f // not valid, skip key test
	tst REG_KEY_STATE
	brne state1 // key released -> start over
1:

	tst REG_TIMER
	brne state4 // not yet done -> loop

	// reset!
	ldi REG_TIMER, TIME_LINE_LOW // init timer
	sbi _SFR_IO_ADDR(DDR), RESET_BIT // set to output, port=0 -> low

	// toggle leds
	#ifdef LED1_BIT
		cbi _SFR_IO_ADDR(DDR), LED1_BIT // set to input, port=0 -> n/c
	#endif
	#ifdef LED2_BIT
		sbi _SFR_IO_ADDR(DDR), LED2_BIT // set to output, port=0 -> low
	#endif
  
state5: // wait for TIME_LINE_LOW
	tst REG_TIMER
	brne state5 // not yet done -> loop
	
	// reset done
	ldi REG_TIMER, TIME_BLINK_LED - TIME_LINE_LOW // init timer
	cbi _SFR_IO_ADDR(DDR), RESET_BIT // set to input, port=0 -> n/c
	
state6: // wait for TIME_BLINK_LED (minus the already waied TIME_LINE_LOW)
	tst REG_TIMER
	brne state6 // not yet done -> loop

	// toggle leds
	#ifdef LED1_BIT
		sbi _SFR_IO_ADDR(DDR), LED1_BIT // set to output, port=0 -> low
	#endif
	#ifdef LED2_BIT
		cbi _SFR_IO_ADDR(DDR), LED2_BIT // set to input, port=0 -> n/c
	#endif
  
  	// start over
	rjmp state0
.endfunc

/*
** TIMER OVERFLOW
*/

.global sig_overflow0
.func sig_overflow0
sig_overflow0:
	// save SREG
	in REG_SREG, _SFR_IO_ADDR(SREG)
	// "entprellung" of the RESTORE KEY
	mov REG_KEY_VALID, REG_KEY_STATE
	in REG_KEY_STATE, _SFR_IO_ADDR(PIN)
	andi REG_KEY_STATE, (1<<RESTORE_IN_BIT)
	eor REG_KEY_VALID, REG_KEY_STATE
	// decrement timer
	dec REG_TIMER
	// restore SREG
	out _SFR_IO_ADDR(SREG), REG_SREG
	reti
.endfunc
