/*

	resstore-reset.asm by ALeX Kazik

	Code+Docs: https://github.com/alexkazik/restore-reset
	Homepage: http://alex.kazik.de/232/restore-reset

	License: Creative Commons Attribution 3.0 Unported License
	http://creativecommons.org/licenses/by/3.0/

*/


#include <avr/io.h>

/*
** REGISTER DEFINITION
*/

// Registers 0..15 are not used, because some AVRs don't have such
#define REG_SREG 16 // to store the SREG in the interrupt
#define REG_KEY_VALID 17 // is the REG_KEY_STATE valid (0) or invalid (!=0)
#define REG_KEY_STATE 18 // the state of the key (only valid if REG_KEY_VALID is 0)
#define REG_TIMER 19 // the timer
// Registers 20..29 are just not used
// Registers 30,31 are not used, so they can be used as a stack for those AVR's
//      which don't have SRAM (two bytes are enough, just interrpt and return, no rcall)

/*
** I/O DEFINITION
*/

// ALL PINS MUST BE ON ONE PORT
#define PORT PORTB
#define PIN PINB
#define DDR DDRB

// THE PINS
#define RESTORE_IN_BIT 0
#define RESTORE_OUT_BIT 1
#define RESET_BIT 2
// you can comment the LEDs out (one, another or both) if you don't have/want LEDs
#define LED1_BIT 3
#define LED2_BIT 4

/*
** TIMING DEFINITION
*/

#define TIME_BASE 20000 // how many usec until the timer produces an overflow

#define TIME_LINE_LOW (200000/TIME_BASE) // how long should the restore/reset line low
#define TIME_LINE_PAUSE (200000/TIME_BASE) // how long the restore/reset line shouln't be pulled low again
#define TIME_RESET (2000000/TIME_BASE) // how long you should press the restore key to trigger a reset
#define TIME_BLINK_LED (500000/TIME_BASE) // how long should the LED blink
#define DOUBLE_RESET // do a second reset after the twice the blink time (once actually blinking)

#if TIME_LINE_LOW < 1 || TIME_LINE_PAUSE < 1 || TIME_RESET < 1 || TIME_BLINK_LED < 1
	#error "times must be > BASE"
#elif TIME_RESET - (TIME_LINE_LOW + TIME_LINE_PAUSE) < 1
	#error "time for reset is too low"
#elif TIME_RESET - (TIME_LINE_LOW + TIME_LINE_PAUSE) > 255
	#error "time for reset is too high"
#elif (defined(LED1_BIT) || defined(LED2_BIT)) && (TIME_BLINK_LED - TIME_LINE_LOW < 1)
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
	.word 0xffff // vector 1, unused
	.word 0xffff // vector 2, unused
	rjmp sig_overflow0 // vector 3
#elif defined(__AVR_ATtiny25__) || defined(__AVR_ATtiny45__) || defined(__AVR_ATtiny85__)
	rjmp main // vector 0
	.word 0xffff // vector 1, unused
	.word 0xffff // vector 2, unused
	.word 0xffff // vector 3, unused
	.word 0xffff // vector 4, unused
	rjmp sig_overflow0 // vector 5
#elif defined(__AVR_ATtiny4__) || defined(__AVR_ATtiny5__) || defined(__AVR_ATtiny9__) || defined(__AVR_ATtiny10__)
	rjmp main // vector 0
	.word 0xffff // vector 1, unused
	.word 0xffff // vector 2, unused
	.word 0xffff // vector 3, unused
	rjmp sig_overflow0 // vector 4
#elif defined(__AVR_ATtiny24__) || defined(__AVR_ATtiny24A__) || defined(__AVR_ATtiny44__) || defined(__AVR_ATtiny44A__) || defined(__AVR_ATtiny84__)
	rjmp main // vector 0
	.word 0xffff // vector 1, unused
	.word 0xffff // vector 2, unused
	.word 0xffff // vector 3, unused
	.word 0xffff // vector 4, unused
	.word 0xffff // vector 5, unused
	.word 0xffff // vector 6, unused
	.word 0xffff // vector 7, unused
	.word 0xffff // vector 8, unused
	.word 0xffff // vector 9, unused
	.word 0xffff // vector 10, unused
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

	// REG_SREG is used as a temporary register; it's only ised in the interrupt, which is disabled at this point

	// setup stack
	// hi byte of the stack, only used for systems with >128 bytes of sram
	#ifdef SPH
		ldi REG_SREG, RAMEND >> 8
		out _SFR_IO_ADDR(SPH), REG_SREG
	#endif
	// low byte of the stack
	ldi REG_SREG, RAMEND & 0xff
	out _SFR_IO_ADDR(SPL), REG_SREG

	// only for initial LED states
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

	// init I/O

	ldi REG_SREG, LED1_MASK | LED2_MASK // the mask is 0 if the the LED is not known
	out _SFR_IO_ADDR(DDR), REG_SREG // LEDs output, others input
	ldi REG_SREG, (1<<RESTORE_IN_BIT)
	out _SFR_IO_ADDR(PORT), REG_SREG // pulllup for REST_IN, others without pullup / output low

	// init timer! to the correct TIME_BASE
#if defined(__AVR_ATtiny13__) || defined(__AVR_ATtiny13A__) || defined(__AVR_ATtiny24__) || defined(__AVR_ATtiny24A__) || defined(__AVR_ATtiny44__) || defined(__AVR_ATtiny44A__) || defined(__AVR_ATtiny84__)
	#if TIME_BASE != 20000 || F_CPU != 1000000
		#error "currently only 20ms@1Mhz as base are supported"
	#endif
	// time to overflow 78(.125) * (clock/256) ~= 20ms
	ldi REG_SREG, 78
	out _SFR_IO_ADDR(OCR0A), REG_SREG
	// ctc mode (two of the three WGM bits)
	ldi	REG_SREG, (1<<WGM01) | (1<<WGM00)
	out _SFR_IO_ADDR(TCCR0A), REG_SREG
	// ctc mode (the last of the three WGM bits)
	// AND scaler: clock/256
	ldi REG_SREG, (1<<WGM02) | (1<<CS02)
	out _SFR_IO_ADDR(TCCR0B), REG_SREG
	// enable interrupt
	ldi REG_SREG, (1<<TOIE0)
	out _SFR_IO_ADDR(TIMSK0), REG_SREG
#elif defined(__AVR_ATtiny25__) || defined(__AVR_ATtiny45__) || defined(__AVR_ATtiny85__)
	#if TIME_BASE != 20000 || F_CPU != 1000000
		#error "currently only 20ms@1Mhz as base are supported"
	#endif
	// time to overflow 78(.125) * (clock/256) ~= 20ms
	ldi REG_SREG, 78
	out _SFR_IO_ADDR(OCR0A), REG_SREG
	// ctc mode (two of the three WGM bits)
	ldi	REG_SREG, (1<<WGM01) | (1<<WGM00)
	out _SFR_IO_ADDR(TCCR0A), REG_SREG
	// ctc mode (the last of the three WGM bits)
	// AND scaler: clock/256
	ldi REG_SREG, (1<<WGM02) | (1<<CS02)
	out _SFR_IO_ADDR(TCCR0B), REG_SREG
	// enable interrupt
	ldi REG_SREG, (1<<TOIE0)
	out _SFR_IO_ADDR(TIMSK), REG_SREG // <-- the only differenct to attiny13/attinyX4
#elif defined(__AVR_ATtiny4__) || defined(__AVR_ATtiny5__) || defined(__AVR_ATtiny9__) || defined(__AVR_ATtiny10__)
	#if TIME_BASE != 20000 || F_CPU != 1000000
		#error "currently only 20ms@1Mhz as base are supported"
	#endif
	// time to overflow 78(.125) * (clock/256) ~= 20ms
	ldi REG_SREG, 78 >> 8
	out _SFR_IO_ADDR(OCR0AH), REG_SREG
	ldi REG_SREG, 78 & 0xff
	out _SFR_IO_ADDR(OCR0AL), REG_SREG
	// ctc mode (two of the four WGM bits)
	ldi	REG_SREG, (1<<WGM01) | (1<<WGM00)
	out _SFR_IO_ADDR(TCCR0A), REG_SREG
	// ctc mode (the last two of the four WGM bits)
	// AND scaler: clock/256
	ldi REG_SREG, (1<<WGM02) | (1<<WGM03) | (1<<CS02)
	out _SFR_IO_ADDR(TCCR0B), REG_SREG
	// enable interrupt
	ldi REG_SREG, (1<<TOIE0)
	out _SFR_IO_ADDR(TIMSK0), REG_SREG
#else
	#error "unknown AVR"
#endif

	// prepare launch
	ldi REG_KEY_VALID, (1<<RESTORE_IN_BIT) // key not valid
	ldi REG_KEY_STATE, (0<<RESTORE_IN_BIT) // key pressed
	// set LEDs (1 is already on, 2 will be switched off)
	#ifdef LED2_BIT
		cbi _SFR_IO_ADDR(DDR), LED2_BIT // set to input, port=0 -> n/c
	#endif
	// enable interrupt
	sei

	/*
	** the real program
	*/

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
	sbi _SFR_IO_ADDR(DDR), RESTORE_OUT_BIT // set to output, port=0 -> low
	ldi REG_TIMER, TIME_LINE_LOW // init timer

state2: // wait for TIME_LINE_LOW
	tst REG_TIMER
	brne state2 // not yet done -> loop

	// restore RESTORE_OUT for (at least) TIME_LINE_PAUSE
	cbi _SFR_IO_ADDR(DDR), RESTORE_OUT_BIT // set to input, port=0 -> n/c
	ldi REG_TIMER, TIME_LINE_PAUSE // init timer

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
	sbi _SFR_IO_ADDR(DDR), RESET_BIT // set to output, port=0 -> low
	ldi REG_TIMER, TIME_LINE_LOW // init timer

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
	cbi _SFR_IO_ADDR(DDR), RESET_BIT // set to input, port=0 -> n/c
#if defined(DOUBLE_RESET) || defined(LED1_BIT) || defined(LED2_BIT)
	ldi REG_TIMER, TIME_BLINK_LED - TIME_LINE_LOW // init timer

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
#endif
#if defined(DOUBLE_RESET)

	ldi REG_TIMER, TIME_BLINK_LED // init timer

state7: // wait for TIME_BLINK_LED or release of the restore key
	tst REG_KEY_VALID
	brne 1f // not valid, skip key test
	tst REG_KEY_STATE
	brne state1 // key released -> start over
1:

	tst REG_TIMER
	brne state7 // not yet done -> loop

	// reset again
	sbi _SFR_IO_ADDR(DDR), RESET_BIT // set to output, port=0 -> low
	ldi REG_TIMER, TIME_LINE_LOW // init timer

state8: // wait for TIME_LINE_LOW
	tst REG_TIMER
	brne state8 // not yet done -> loop

	// reset done
	cbi _SFR_IO_ADDR(DDR), RESET_BIT // set to input, port=0 -> n/c
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
	// debounce the RESTORE KEY
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
