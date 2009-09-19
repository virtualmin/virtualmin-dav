#!/usr/local/bin/perl
# Show a list of DAV sub-directories to which users can be granted access

require './virtualmin-dav-lib.pl';
&ReadParse();
$in{'dom'} || &error($text{'index_edom'});
$d = &virtual_server::get_domain($in{'dom'});
$d || &error($text{'index_edom2'});
$d->{$module_name} || &error($text{'index_edav'});

$ddesc = &virtual_server::domain_in($d);
&ui_print_header($ddesc, $text{'shares_title'}, "");

@shares = &list_dav_shares($d);
@links = ( "<a href='edit_share.cgi?dom=$in{'dom'}&new=1'>".
	   $text{'shares_add'}."</a>" );
if (@shares) {
	# Show list of shares
	print &ui_columns_start([ $text{'shares_dir'},
				  $text{'shares_relpath'},
				  $text{'shares_realm'},
				  $text{'shares_users'} ], 100);
	foreach $s (@shares) {
		print &ui_columns_row([
			"<a href='edit_share.cgi?dom=$in{'dom'}&".
			  "dir=$s->{'dir'}'>$s->{'fulldir'}</a>",
			$s->{'relpath'},
			$s->{'realm'},
			$users,
			]);
		}
	print &ui_columns_end();
	}
else {
	print "<b>$text{'shares_none'}</b> <p>\n";
	print &ui_links_row(\@links);
	}

&ui_print_footer(&virtual_server::domain_footer_link($d),
		 "", $text{'index_return'});

