use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'list_shares.cgi' );
strict_ok( 'list_shares.cgi' );
warnings_ok( 'list_shares.cgi' );
