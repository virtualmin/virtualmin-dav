#!/usr/local/bin/perl
# Show DAV settings for some domain
use strict;
use warnings;
our (%text, %in, %config);
our $module_name;

require './virtualmin-dav-lib.pl';
&ReadParse();

my $d;
my @doms;
if (!$in{'dom'}) {
	# Default to first domain with DAV
	@doms = grep { $_->{$module_name} }
		     &virtual_server::list_visible_domains();
	@doms || &error($text{'index_edom'});
	($d) = $doms[0];
	}
else {
	# Get specific domain
	$d = &virtual_server::get_domain($in{'dom'});
	$d || &error($text{'index_edom2'});
	}
my $ddesc = &virtual_server::domain_in($d);

&ui_print_header($ddesc, $text{'index_title'}, "", undef, 1, 1);

$d->{$module_name} || &error($text{'index_edav'});

print &ui_form_start("save.cgi");
print &ui_hidden("dom", $d->{'id'});
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
my @davusers = &list_users($d);
my @domusers = &virtual_server::list_domain_users($d);
my @cannot;
foreach my $u (@domusers) {
	my ($davu) = grep { $_->{'user'} eq &dav_username($u, $d) } @domusers;
	if ($davu && !defined($u->{'plainpass'}) && !$u->{'pass_digest'} &&
	    !$u->{'domainowner'}) {
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

