#!perl -w
use strict;
use Test::More tests => 6;
use_ok('Mariachi::Message');

my $m = Mariachi::Message->new(<<'MAIL');
To: Marty McFly <marty@mcfly.org>
From: Doc Brown <brown@madinventors.org>
Subject: Delorean

On Wednesday, 5th of March, Marty McFly said
> Wait a minute, Doc. Ah... Are you telling me you built a time machine
> ... out of a DeLorean?  

The way I see it, if you're gonna build a time machine into a car, why 
not do it with some style? 
MAIL

isa_ok( $m, 'Mariachi::Message' );

is($m->first_lines(),"The way I see it, if you're gonna build a time machine into a car, why ");
is($m->first_lines(2),"The way I see it, if you're gonna build a time machine into a car, why \nnot do it with some style? ");


my $m2 = Mariachi::Message->new(<<'MAIL');
From: sam.baines@hillvalley.com
To: stella.baines@hillvalley.com
Date: z

On Thursday, 6th of March, Stella Baines said
> He's a very strange man

He's an idiot. Comes from upbringing. His parents are 
probably idiots too. Lorraine, if you ever have a kid 
that acts that way I'll disown you.

-- 
But we do have a sig
MAIL

is($m2->first_lines(2),"He's an idiot. Comes from upbringing. His parents are \nprobably idiots too. Lorraine, if you ever have a kid ");
is($m2->first_para(),"He's an idiot. Comes from upbringing. His parents are \nprobably idiots too. Lorraine, if you ever have a kid \nthat acts that way I'll disown you.");

