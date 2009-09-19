#!/usr/local/bin/perl
# Show a form to create or edit a DAV share

require './virtualmin-dav-lib.pl';
&foreign_require("virtual-server", "virtual-server-lib.pl");
&ReadParse();
$in{'dom'} || &error($text{'index_edom'});
$d = &virtual_server::get_domain($in{'dom'});
$d || &error($text{'index_edom2'});
$ddesc = &virtual_server::domain_in($d);

if ($in{'new'}) {
	&ui_print_header($ddesc, $text{'share_title1'}, "");
	$s = { 'samepath' => 1 };
	}
else {
	($s) = grep { $_->{'dir'} eq $in{'dir'} } &list_dav_shares($d);
	$s || &error($text{'share_egone'});
	&ui_print_header($ddesc, $text{'share_title2'}, "");
	}

print &ui_form_start("save_share.cgi", "post");
print &ui_hidden("dom", $in{'dom'});
print &ui_hidden("new", $in{'new'});
print &ui_hidden("dir", $in{'dir'});
print &ui_table_start($text{'share_header'}, undef, 2);

# DAV path
if ($in{'new'}) {
	print &ui_table_row($text{'share_dir'},
			    "<tt>/dav/</tt>".&ui_textbox("dir", undef, 20));
	}
else {
	print &ui_table_row($text{'share_dir'}, "<tt>$s->{'fulldir'}</tt>");
	}

# Actual directory under home
print &ui_table_row($text{'share_path'},
	&ui_opt_textbox("relpath", $s->{'samepath'} ? undef : $s->{'relpath'},
			30, $text{'share_samepath'}));

# Realm name
print &ui_table_row($text{'share_realm'},
	&ui_textbox("realm", $s->{'realm'}, 50));

print &ui_table_end();
if ($in{'new'}) {
	print &ui_form_end([ [ undef, $text{'create'} ] ]);
	}
else {
	print &ui_form_end([ [ undef, $text{'save'} ],
			     [ 'delete', $text{'delete'} ] ]);
	}

&ui_print_footer("list_shares.cgi", $text{'shares_return'},
		 &virtual_server::domain_footer_link($d));
