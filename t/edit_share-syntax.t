use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'edit_share.cgi' );
strict_ok( 'edit_share.cgi' );
warnings_ok( 'edit_share.cgi' );
