#!/usr/local/bin/perl
# Show DAV settings for some domain

require './virtualmin-dav-lib.pl';
&foreign_require("virtual-server", "virtual-server-lib.pl");
&ReadParse();
$in{'dom'} || &error($text{'index_edom'});
$d = &virtual_server::get_domain($in{'dom'});
$d || &error($text{'index_edom2'});
$ddesc = &virtual_server::domain_in($d);

&ui_print_header($ddesc, $text{'index_title'}, "", undef, 1, 1);

$d->{$module_name} || &error($text{'index_edav'});

print &ui_form_start("save.cgi");
print &ui_hidden("dom", $in{'dom'}),"\n";
print &ui_table_start($text{'index_header'}, undef, 2);

# Current authentication mode
$d->{'dav_auth'} ||= $config{'auth'};
print &ui_table_row($text{'index_auth'},
		    &ui_select("auth", $d->{'dav_auth'},
			[ [ "Basic", $text{'index_basic'} ],
			  [ "Digest", $text{'index_digest'} ] ]));

# Current username mode
$d->{'dav_name_mode'} = $config{'name_mode'} if (!defined($d->{'dav_name_mode'}));
print &ui_table_row($text{'index_mode'},
		    &ui_select("mode", $d->{'dav_name_mode'},
			[ [ 0, $text{'index_mode0'} ],
			  [ 1, $text{'index_mode1'} ],
			  [ 2, $text{'index_mode2'} ] ]));

# Number of DAV users
@davusers = &list_users($d);
@domusers = &virtual_server::list_domain_users($d);
foreach $u (@domusers) {
	($davu) = grep { $_->{'user'} eq &dav_username($u, $d) } @domusers;
	if ($davu && !defined($u->{'plainpass'}) && !$u->{'domainowner'}) {
		push(@cannot, $u->{'user'});
		}
	}
print &ui_table_row($text{'index_users'},
	@cannot ? &text('index_ucannot', scalar(@davusers), scalar(@cannot))
		: &text('index_ucount', scalar(@davusers)));
if (@cannot) {
	print &ui_table_row($text{'index_users2'},
			    join(" ", map { "<tt>$_</tt>" } @cannot));
	}

print &ui_table_end();
print &ui_form_end([ [ "change", $text{'index_change'} ] ]);

&ui_print_footer("/", $text{'index'});


1;

