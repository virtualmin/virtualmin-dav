#!/usr/local/bin/perl
# Show a form to create or edit a DAV share
use strict;
use warnings;
our (%text, %in); 

require './virtualmin-dav-lib.pl';
&ReadParse();
$in{'dom'} || &error($text{'index_edom'});
my $d = &virtual_server::get_domain($in{'dom'});
$d || &error($text{'index_edom2'});
my $ddesc = &virtual_server::domain_in($d);

my $s;
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
print &ui_table_start($text{'share_header'}, undef, 2);

# DAV path
if ($in{'new'}) {
	print &ui_table_row($text{'share_dir'},
			    "<tt>http://$d->{'dom'}/dav/</tt>".
			    &ui_textbox("dir", undef, 20));
	}
else {
	print &ui_table_row($text{'share_dir'},
			    "<tt>http://$d->{'dom'}$s->{'fulldir'}</tt>");
	print &ui_hidden("dir", $in{'dir'});
	}

# Actual directory under home
if ($s->{'main'}) {
	print &ui_table_row($text{'share_path'}, "<tt>$s->{'relpath'}</tt>");
	}
else {
	print &ui_table_row($text{'share_path'},
		&ui_opt_textbox("relpath",
				$s->{'samepath'} ? undef : $s->{'relpath'},
				30, $text{'share_samepath'},
				$text{'share_otherpath'}));
	}

# Realm name (if not in digest mode)
if ($d->{'dav_auth'} ne 'Digest') {
	print &ui_table_row($text{'share_realm'},
		&ui_textbox("realm", $s->{'realm'}, 50));
	}

# Allowed users
my @allusers = map { [ $_->{'user'}, $_->{'user'} ] } &list_users($d);
my @selusers = $s->{'users'} ? ( map { [ $_, $_ ] } @{$s->{'users'}} )
			  : ( );
print &ui_table_row($text{'share_users'},
	&ui_radio("users_def", $s->{'users'} ? 0 : 1,
		  [ [ 1, $text{'share_users1'} ],
		    [ 0, $text{'share_users0'} ] ])."<br>\n".
	&ui_multi_select("users", \@selusers, \@allusers, 10, 1, 0,
			 $text{'share_allusers'}, $text{'share_selusers'}));

# Read-write users
# Disabled for now - all users are read/write
#@selrwusers = $s->{'rwusers'} ? ( map { [ $_, $_ ] } @{$s->{'rwusers'}} )
#			      : ( );
#print &ui_table_row($text{'share_rwusers'},
#	&ui_radio("rwusers_def", $s->{'rwusers'} ? 0 : 1,
#		  [ [ 1, $text{'share_users1'} ],
#		    [ 0, $text{'share_users0'} ] ])."<br>\n".
#	&ui_multi_select("rwusers", \@selrwusers, \@allusers, 10, 1, 0,
#			 $text{'share_allusers'}, $text{'share_selusers'}));

print &ui_table_end();
if ($in{'new'}) {
	print &ui_form_end([ [ undef, $text{'create'} ] ]);
	}
else {
	print &ui_form_end([ [ undef, $text{'save'} ],
			     $s->{'main'} ? ( ) : ( [ 'delete',
						      $text{'delete'} ] ) ]);
	}

&ui_print_footer("list_shares.cgi?dom=$in{'dom'}", $text{'shares_return'},
		 &virtual_server::domain_footer_link($d));

