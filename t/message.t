#!perl -w
use strict;
use Test::More tests => 4;
use_ok('Mariachi::Message');

my $m = Mariachi::Message->new(<<'MAIL');
From: Doc Brown <doc@inventors>
To: world
Message-Id: 1.21@dealers
Date: Sat, 12 November 1955 22:02:00
Subject: Time Travel

I have a hunch
MAIL

isa_ok( $m, 'Mariachi::Message' );

is( $m->header('from'), 'Doc Brown <doc@inventors>', "get the from header" );
is( $m->from,           'Doc Brown', "sanitised from" );
