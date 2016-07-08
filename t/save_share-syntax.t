use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'save_share.cgi' );
strict_ok( 'save_share.cgi' );
warnings_ok( 'save_share.cgi' );
