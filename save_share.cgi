#!/usr/local/bin/perl
# Create, update or delete a DAV share

require './virtualmin-dav-lib.pl';
&foreign_require("virtual-server", "virtual-server-lib.pl");
&ReadParse();
$in{'dom'} || &error($text{'index_edom'});
$d = &virtual_server::get_domain($in{'dom'});
$d || &error($text{'index_edom2'});
@shares = &list_dav_shares($d);
&error_setup($text{'share_err'});
&virtual_server::obtain_lock_web($d);

if (!$in{'new'}) {
	($s) = grep { $_->{'dir'} eq $in{'dir'} } @shares;
        $s || &error($text{'share_egone'});
	}
else {
	$s = { };
	}

if ($in{'delete'}) {
	# Just delete it
	&delete_dav_share($d, $d);
	}
else {
	# Validate inputs
	if ($in{'new'}) {
		# Check for clash
		($clash) = grep { $->{'dir'} eq $in{'dir'} } @shares;
		$clash && &error($text{'share_eclash'});
		$in{'dir'} =~ /^\S+$/ && $in{'dir'} !~ /^\// ||
			&error($text{'share_edir'});
		$s->{'dir'} = $in{'dir'};
		}

	if ($in{'relpath_def'}) {
		# Same dir under public_html
		$s->{'samepath'} = 1;
		$s->{'path'} = &virtual_server::public_html_dir($d).
			       "/".$in{'dir'};
		}
	else {
		$in{'relpath'} =~ /^\S+$/ && $in{'relpath'} !~ /^\// ||
			&error($text{'share_epath'});
		$s->{'samepath'} = 0;
		$s->{'path'}  = $d->{'home'}.'/'.$in{'relpath'};
		}

	$in{'realm'} =~ /\S/ || &error($text{'share_erealm'});
	$s->{'realm'} = $in{'realm'};

	if ($in{'new'}) {
		&create_dav_share($d, $s);
		}
	else {
		&modify_dav_share($d, $s);
		}
	}


&virtual_server::release_lock_web($d);
&webmin_log($in{'delete'} ? 'delete' : $in{'new'} ? 'create' : 'modify',
	    'share', $s->{'dir'});
&redirect("list_shares.cgi");

