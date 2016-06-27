#!/usr/local/bin/perl
# Show a list of DAV sub-directories to which users can be granted access
use strict;
use warnings;
our (%in, %text);
our $module_name;

require './virtualmin-dav-lib.pl';
&ReadParse();
$in{'dom'} || &error($text{'index_edom'});
my $d = &virtual_server::get_domain($in{'dom'});
$d || &error($text{'index_edom2'});
$d->{$module_name} || &error($text{'index_edav'});
my $digest = $d->{'dav_auth'} ne 'Digest' ? 0 : 1;

my $ddesc = &virtual_server::domain_in($d);
&ui_print_header($ddesc, $text{'shares_title'}, "");

my @shares = &list_dav_shares($d);
my @links = ( "<a href='edit_share.cgi?dom=$in{'dom'}&new=1'>".
	          $text{'shares_add'}."</a>" );
if (@shares) {
	# Show list of shares
	print &ui_links_row(\@links);
	print &ui_columns_start([ $text{'shares_dir'},
				  $text{'shares_relpath'},
				  $digest ? ( ) : ( $text{'shares_realm'} ),
				  $text{'shares_users'},
				  $text{'shares_rwusers'},
				], 100);
	foreach my $s (@shares) {
		print &ui_columns_row([
			"<a href='edit_share.cgi?dom=$in{'dom'}&".
			  "dir=$s->{'dir'}'>$s->{'fulldir'}</a>",
			$s->{'relpath'},
			$digest ? ( ) : ( $s->{'realm'} ),
			&make_nice_users($s->{'users'}),
			&make_nice_users($s->{'rwusers'}),
			]);
		}
	print &ui_columns_end();
	}
else {
	print "<b>$text{'shares_none'}</b> <p>\n";
	}
print &ui_links_row(\@links);

&ui_print_footer(&virtual_server::domain_footer_link($d));

sub make_nice_users
{
my ($ulist) = @_;
if (!$ulist) {
	return "<i>$text{'shares_all'}</i>";
	}
else {
	my @users = @$ulist;
	if (@users > 4) {
		@users = ( @users[0..3],
		   &text('shares_uc', scalar(@users)-4) );
		}
	return join(" , ", @users);
	}
}
