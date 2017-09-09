restore-reset
=============

This project aims to use the C64 Restore key to perform an reset. Useful for
people who don't have an Reset switch in their C64 and/or don't want to
make holes in their C64.

You need an ATtiny13/A (or other), and a few resitors/capacitator only.
So it should cost less than 2€ in total.

It started in the [forum64][].

[forum64]: https://www.forum64.de/index.php?thread/44323-beleuchteter-resettaster/

How it works
------------
First the Restore key is debounced. When you press the Restore key an restore signal is sent
to the C64 (for 200ms). When you hold the Restore key longer than 2sec, then
a reset is sent (also for 200ms).

Additional it's signalled when a reset is issued. You can, for example,
replace the regular power led of your C64 by a duo led and connect it to the circuit
(see scematics). The one led will be on only when a reset is issued (for 0.5sec),
and the other is otherwise on.

When configured a second reset is issed after double the blink time (with or without leds configured).
This may be useful when you have some kind of hardware which expects such a behavior.

Scematics
---------

The scematics are from [Novlammoth](https://www.forum64.de/index.php?user/4215-novlammoth/).

You have to cut one line of the keyboard cable, the restore line, and connect both lines
to the attiny: restore in - the line to the key, restore out - the line to the c64.
One line is, of course, the reset line. And last but not least power and ground.

Instead of the ATtiny13/A you can also use almost any ATtiny/mega. The code is prepared
for ATtiny 13,13A,25,45,85,4,5,9,10,24,24A,44,44A,48 - just pick the one which is available.

The use of the LEDs is optional, if you don't want/have/need them, just comment out the
line(s) in the code. You can also disable only one of the LEDs.

The double reset feature can be disabled by commenting out.

You can use other PINs if you want, just change the configuration in main.asm.

Compile
-------

Configure the Makefile and main.asm to you used ATtiny, and LED/PIN configuration.
And "make" to buid, and "make program" to program it.

License
-------

[Creative Commons Attribution 3.0 Unported License](http://creativecommons.org/licenses/by/3.0/)
