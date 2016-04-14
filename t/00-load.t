#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'File::Follow' ) || print "Bail out!\n";
}

diag( "Testing File::Follow $File::Follow::VERSION, Perl $], $^X" );
