# Defines functions for this feature

require 'virtualmin-dav-lib.pl';
&load_theme_library();

$input_name = $module_name;
$input_name =~ s/[^A-Za-z0-9]/_/g;

# feature_name()
# Returns a short name for this feature
sub feature_name
{
return $text{'feat_name'};
}

# feature_losing(&domain)
# Returns a description of what will be deleted when this feature is removed
sub feature_losing
{
return $text{'feat_losing'};
}

# feature_disname(&domain)
# Returns a description of what will be turned off when this feature is disabled
sub feature_disname
{
return $text{'feat_disname'};
}

# feature_label(in-edit-form)
# Returns the name of this feature, as displayed on the domain creation and
# editing form
sub feature_label
{
local ($edit) = @_;
return $edit ? $text{'feat_label2'} : $text{'feat_label'};
}

sub feature_hlink
{
return "label";
}

# feature_check()
# Returns undef if all the needed programs for this feature are installed,
# or an error message if not
sub feature_check
{
&virtual_server::require_apache();
return $text{'feat_eapache'} if (!$apache::httpd_modules{'mod_dav'});
if ($config{'auth'} eq 'Digest') {
	# Check for htdigest command
	&foreign_require("htaccess-htpasswd", "htaccess-lib.pl");
	if (!$htaccess_htpasswd::htdigest_command) {
		return &text('feat_edigest', "<tt>htdigest</tt>");
		}
	}
return undef;
}

# feature_depends(&domain)
# Returns undef if all pre-requisite features for this domain are enabled,
# or an error message if not
sub feature_depends
{
return $_[0]->{'web'} ? undef : $text{'feat_edepweb'};
}

# feature_clash(&domain)
# Returns undef if there is no clash for this domain for this feature, or
# an error message if so
sub feature_clash
{
return undef;
}

# feature_suitable([&parentdom], [&aliasdom], [&subdom])
# Returns 1 if some feature can be used with the specified alias and
# parent domains
sub feature_suitable
{
return $_[1] || $_[2] ? 0 : 1;		# not for alias domains
}

# feature_setup(&domain)
# Called when this feature is added, with the domain object as a parameter
sub feature_setup
{
&$virtual_server::first_print($text{'setup_dav'});
&virtual_server::obtain_lock_web($_[0]);
local $any;
$_[0]->{'dav_auth'} ||= $config{'auth'};
$_[0]->{'dav_name_mode'} = $config{'name_mode'} if (!defined($_[0]->{'dav_name_mode'}));
$any++ if (&add_dav_directives($_[0], $_[0]->{'web_port'}));
$any++ if ($_[0]->{'ssl'} &&
	   &add_dav_directives($_[0], $_[0]->{'web_sslport'}));
if (!$any) {
	&$virtual_server::second_print(
		$virtual_server::text{'delete_noapache'});
	}
else {
	# Added Apache config .. now create other files
	local $passwd_file = &digest_file($_[0]);
	if (!-d "$_[0]->{'home'}/etc") {
		&virtual_server::make_dir_as_domain_user(
			$_[0], "$_[0]->{'home'}/etc", 0755);
		}
	if (!-r $passwd_file) {
		&virtual_server::open_tempfile_as_domain_user(
			$_[0], PASSWD, ">$passwd_file", 0, 1);
		&virtual_server::close_tempfile_as_domain_user($_[0], PASSWD);
		}
	&virtual_server::set_permissions_as_domain_user(
		$_[0], 0665, $passwd_file);

	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	&virtual_server::register_post_action(\&virtual_server::restart_apache);

	# Grant access to the domain's owner
	my $uinfo;
	if (!$d->{'parent'} &&
	    ($uinfo = &virtual_server::get_domain_owner($_[0]))) {
		&$virtual_server::first_print($text{'setup_davuser'});
		local $un = &dav_username($uinfo, $_[0]);
		local $newuser = { 'user' => $un,
				   'enabled' => 1 };
		if ($_[0]->{'dav_auth'} eq 'Digest') {
			# Do Digest encryption
			$newuser->{'pass'} = &htaccess_htpasswd::digest_password
				($un, $_[0]->{'dom'}, $_[0]->{'pass'});
			}
		else {
			# Copy Unix crypted pass
			$newuser->{'pass'} = $uinfo->{'pass'};
			}
		&virtual_server::write_as_domain_user($_[0],
			sub { &htaccess_htpasswd::create_user(
				$newuser, $passwd_file) });
		&$virtual_server::second_print(
			$virtual_server::text{'setup_done'});
		}
	}

# Make sure /dav isn't proxied
if (defined(&virtual_server::setup_noproxy_path)) {
	&virtual_server::setup_noproxy_path(
		$_[0], { }, undef, { 'path' => '/dav/' }, 1);
	}

&virtual_server::release_lock_web($_[0]);
}

# feature_modify(&domain, &olddomain)
# Called when a domain with this feature is modified
sub feature_modify
{
if ($_[0]->{'dom'} ne $_[1]->{'dom'}) {
	# Change domain on DAV users
	&virtual_server::obtain_lock_web($_[0]);
	&$virtual_server::first_print($text{'save_dav'});
	local @users = &list_users($_[0]);
	foreach $e (@users) {
		$u->{'dom'} = $_[0]->{'dom'};
		$u->{'user'} =~ s/$_[1]->{'dom'}/$_[0]->{'dom'}/;
		}
	&save_users($_[0], \@users);

	# Change AuthName in webserver
	&change_dav_directives($_[0], $_[0]->{'web_port'});
	&change_dav_directives($_[0], $_[0]->{'web_sslport'})
		if ($_[0]->{'ssl'});
	&virtual_server::release_lock_web($_[0]);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	}
if ($_[0]->{'pass'} ne $_[1]->{'pass'}) {
	# Change password for domain admin, if he has a DAV account
	local @users = &list_users($_[0]);
	local $uinfo = &virtual_server::get_domain_owner($_[0]);
	local ($un, $suser);
	if ($uinfo) {
		$un = &dav_username($uinfo, $_[0]);
		($suser) = grep { $_->{'user'} eq $un } @users;
		}
	if ($suser) {
		&$virtual_server::first_print($text{'save_davpass'});
                if ($_[0]->{'dav_auth'} eq 'Digest') {
                        $suser->{'pass'} = &htaccess_htpasswd::digest_password(
                                $un, $_[0]->{'dom'}, $_[0]->{'pass'});
                        }
                else {
                        $suser->{'pass'} = &htaccess_htpasswd::encrypt_password(
				$_[0]->{'pass'});
                        }
		&htaccess_htpasswd::modify_user($suser);
		&$virtual_server::second_print(
			$virtual_server::text{'setup_done'});
		}
	}

}

sub change_dav_directives
{
local ($d, $port) = @_;
local $conf = &apache::get_config();
local ($virt, $vconf) = &virtual_server::get_apache_virtual($d->{'dom'}, $port);
return 0 if (!$virt);
local @locs = &apache::find_directive_struct("Location", $vconf);
local ($davloc) = grep { $_->{'words'}->[0] eq "/dav" } @locs;
if ($davloc) {
	local $auth = &apache::find_directive_struct(
		"AuthName", $davloc->{'members'});
	if ($auth) {
		&apache::save_directive("AuthName", [ $d->{'dom'} ],
					$davloc->{'members'}, $conf);
		&flush_file_lines();
		}
	return 1;
	}
return 0;
}

# feature_delete(&domain)
# Called when this feature is disabled, or when the domain is being deleted
sub feature_delete
{
&$virtual_server::first_print($text{'delete_dav'});
&virtual_server::obtain_lock_web($_[0]);
local $any;
$any++ if (&remove_dav_directives($_[0], $_[0]->{'web_port'}));
$any++ if ($_[0]->{'ssl'} &&
	   &remove_dav_directives($_[0], $_[0]->{'web_sslport'}));
&virtual_server::release_lock_web($_[0]);
if (!$any) {
	&$virtual_server::second_print(
		$virtual_server::text{'delete_noapache'});
	}
else {
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	&virtual_server::register_post_action(\&virtual_server::restart_apache);

	# Remove negative proxy for /dav
	if (defined(&virtual_server::delete_noproxy_path)) {
		&virtual_server::delete_noproxy_path(
			$_[0], { }, undef, { 'path' => '/dav/' });
		}
	}
}

# feature_webmin(&domain)
# Returns a list of webmin module names and ACL hash references to be set for
# the Webmin user when this feature is enabled
sub feature_webmin
{
return ( );
}

# feature_backup(&domain, file, &opts, &all-opts)
# Copy the DAV password file file for the domain
sub feature_backup
{
local ($d, $file, $opts) = @_;
&$virtual_server::first_print($text{'feat_backup'});
local $cfile = &digest_file($_[0]);
if (-r $cfile) {
	&copy_source_dest($cfile, $file);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	return 1;
	}
else {
	&$virtual_server::second_print($text{'feat_nofile'});
	return 0;
	}
}

# feature_restore(&domain, file, &opts, &all-opts)
# Called to restore this feature for the domain from the given file
sub feature_restore
{
local ($d, $file, $opts) = @_;
&$virtual_server::first_print($text{'feat_restore'});
&set_ownership_permissions(undef, undef, 0755, $file);
local $cfile = &digest_file($_[0]);
&lock_file($cfile);
local ($ok, $err) = &virtual_server::copy_source_dest_as_domain_user(
			$d, $file, $cfile);
if ($ok) {
	&unlock_file($cfile);
	&virtual_server::set_permissions_as_domain_user($d, 0665, $cfile);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	return 1;
	}
else {
	&unlock_file($cfile);
	&$virtual_server::second_print(&text('feat_nocopy2', $err));
	return 0;
	}
}

sub feature_backup_name
{
return $text{'feat_backup_name'};
}

# feature_validate(&domain)
# Checks if this feature is properly setup for the virtual server, and returns
# an error message if any problem is found
sub feature_validate
{
local ($d) = @_;
local $passwd_file = &digest_file($d);
-r $passwd_file || return &text('feat_evalidatefile', "<tt>$passwd_file</tt>");
local ($virt, $vconf) = &virtual_server::get_apache_virtual($d->{'dom'}, $port);
$virt || return &virtual_server::text('validate_eweb', $d->{'dom'});
local @aliases = &apache::find_directive("Alias", $vconf, 1);
&indexof("/dav", @aliases) >= 0 || return &text('feat_evalidatealias');
local @locs = &apache::find_directive("Location", $vconf, 1);
&indexof("/dav", @locs) >= 0 || return &text('feat_evalidateloc');
return undef;
}

# mailbox_inputs(&user, new, &domain)
# Returns HTML for additional inputs on the mailbox form. These should be
# formatted to appear inside a table.
sub mailbox_inputs
{
local ($user, $new, $dom) = @_;
return undef if ($dom && !$dom->{$module_name});
local $un = &dav_username($user, $dom);
local $duser;
if (!$new) {
	local @users = &list_users($dom);
	($duser) = grep { $_->{'user'} eq $un } @users;
	}
else {
	&read_file("$module_config_directory/defaults.$dom->{'id'}", \%davdefs);
	$duser = { } if ($davdefs{'dav'} || $user->{'webowner'});
	}
local $main::ui_table_cols = 2;
return &ui_table_row(&hlink($text{'mail_dav'}, "dav"),
		     &ui_radio($input_name,
			       $duser || $user->{$module_name} ? 1 : 0,
			       [ [ 1, $text{'yes'} ],
				 [ 0, $text{'no'} ] ]));
}

# mailbox_validate(&user, &olduser, &in, new, &domain)
# Validates inputs generated by mailbox_inputs, and returns either undef on
# success or an error message
sub mailbox_validate
{
local ($user, $olduser, $in, $new, $dom) = @_;
return undef if ($dom && !$dom->{$module_name});
$dom->{'dav_auth'} ||= $config{'auth'};
if ($in->{$input_name}) {
	local @users = &list_users($dom);
	local $un = &dav_username($user, $dom);
	local $oun = &dav_username($olduser, $dom);
	local ($duser) = grep { $_->{'user'} eq $oun } @users;

	# Make sure DAV user doesn't clash
	if ($new || $user->{'user'} ne $olduser->{'user'}) {
		local ($clash) = grep { $_->{'user'} eq $un } @users;
		return &text('mail_clash', $un) if ($clash);
		}

	# Make sure a password is given if needed
	if (!defined($user->{'plainpass'}) &&
	    !$user->{'pass_digest'} &&
	    !$duser &&
	    $user->{'user'} ne $dom->{'user'} &&
	    $dom->{'dav_auth'} eq 'Digest') {
		return $text{'mail_pass'};
		}
	}
return undef;
}

# mailbox_save(&user, &olduser, &in, new, &domain)
# Updates the user based on inputs generated by mailbox_inputs
sub mailbox_save
{
local ($user, $olduser, $in, $new, $dom) = @_;
return 0 if ($dom && !$dom->{$module_name});
&foreign_require("htaccess-htpasswd", "htaccess-lib.pl");
local @users = &list_users($dom);
local $suser;
local $un = &dav_username($user, $dom);
local $oun = &dav_username($olduser, $dom);
local $rv;
$dom->{'dav_auth'} ||= $config{'auth'};

if (!$new) {
	($suser) = grep { $_->{'user'} eq $oun } @users;
	}
if ($in->{$input_name} && !$suser) {
        # Add the user
        local $newuser = { 'user' => $un,
                           'enabled' => 1,
                           'pass' => $user->{'pass_crypt'} ||
				       $user->{'pass'} };
        if ($dom->{'dav_auth'} eq 'Digest') {
                # Set digest password
                $newuser->{'digest'} = 1;
                $newuser->{'dom'} = $dom->{'dom'};
                if ($user->{'user'} eq $dom->{'user'}) {
                        $newuser->{'pass'} = $dom->{'enc_pass_digest'} ||
			    &htaccess_htpasswd::digest_password(
                                $un, $dom->{'dom'}, $dom->{'pass'});
                        }
                elsif ($user->{'passmode'} == 3 ||
		       defined($user->{'plainpass'})) {
                        $newuser->{'pass'} = $user->{'pass_digest'} ||
			    &htaccess_htpasswd::digest_password(
                                $un, $dom->{'dom'}, $user->{'plainpass'});
                        }
                else {
                        $newuser->{'pass'} = "UNKNOWN";
                        }
                }
	&virtual_server::write_as_domain_user($dom,
		sub { &htaccess_htpasswd::create_user(
			$newuser, &digest_file($dom)) });
	$rv = 1;
        }
elsif (!$in->{$input_name} && $suser) {
        # Delete the user
	&virtual_server::write_as_domain_user($dom,
		sub { &htaccess_htpasswd::delete_user($suser) });
	$rv = 0;
        }
elsif ($in->{$input_name} && $suser) {
        # Update the user
        $suser->{'user'} = $un;
        if ($user->{'passmode'} == 3) {
                if ($dom->{'dav_auth'} eq 'Digest') {
                        $suser->{'pass'} = $user->{'enc_pass_digest'} ||
			    &htaccess_htpasswd::digest_password(
                                $un, $dom->{'dom'}, $user->{'plainpass'});
                        }
                else {
                        $suser->{'pass'} = $user->{'pass_crypt'} ||
			    &htaccess_htpasswd::encrypt_password(
				$user->{'plainpass'});
                        }
                }
	&virtual_server::write_as_domain_user($dom,
		sub { &htaccess_htpasswd::modify_user($suser) });
	$rv = 1;
        }
else {
	# Doesn't exist, and never did
	$rv = 0;
	}
return $rv;
}

# mailbox_modify(&user, &old, &domain)
sub mailbox_modify
{
local ($user, $old, $dom) = @_;
return undef if ($dom && !$dom->{$module_name});
&foreign_require("htaccess-htpasswd", "htaccess-lib.pl");
local @users = &list_users($dom);
local $un = &dav_username($user, $dom);
local $oun = &dav_username($user, $dom);
local ($suser) = grep { $_->{'user'} eq $oun } @users;
$dom->{'dav_auth'} ||= $config{'auth'};
if ($suser) {
	# Update the user
	$suser->{'user'} = $un;
	if ($user->{'passmode'} == 3) {
		# Password changed
		if ($dom->{'dav_auth'} eq 'Digest') {
                        $suser->{'pass'} = $user->{'pass_digest'} ||
			    &htaccess_htpasswd::digest_password(
                                $un, $dom->{'dom'}, $user->{'plainpass'});
			}
		else {
                        $suser->{'pass'} = $user->{'pass_crypt'} ||
			    &htaccess_htpasswd::encrypt_password(
				$user->{'plainpass'});
			}
		}
	&virtual_server::write_as_domain_user($dom,
		sub { &htaccess_htpasswd::modify_user($suser) });
	}
}

# mailbox_delete(&user, &domain)
# Removes any extra features for this user
sub mailbox_delete
{
local ($user, $dom) = @_;
return undef if ($dom && !$dom->{$module_name});
&foreign_require("htaccess-htpasswd", "htaccess-lib.pl");
local @users = &list_users($dom);
local $un = &dav_username($user, $dom);
local ($suser) = grep { $_->{'user'} eq $un } @users;
if ($suser) {
	&virtual_server::write_as_domain_user($dom,
		sub { &htaccess_htpasswd::delete_user($suser) });
	}
}

# mailbox_header(&domain)
# Returns a column header for the user display, or undef for none
sub mailbox_header
{
if ($_[0]->{$module_name}) {
	@column_users = &list_users($_[0]);
	return $text{'mail_header'};
	}
else {
	return undef;
	}
}

# mailbox_column(&user, &domain)
# Returns the text to display in the column for some user
sub mailbox_column
{
local ($user, $dom) = @_;
local $un = &dav_username($user, $dom);
local ($duser) = grep { $_->{'user'} eq $un } @column_users;
return $duser ? $text{'yes'} : $text{'no'};
}

# mailbox_defaults_inputs(&defs, &domain)
# Returns HTML for editing defaults for plugin-related settings for new
# users in this virtual server
sub mailbox_defaults_inputs
{
local ($defs, $dom) = @_;
if ($dom->{$module_name}) {
	local %davdefs;
	&read_file("$module_config_directory/defaults.$dom->{'id'}", \%davdefs);
	return &ui_table_row($text{'mail_dav'},
		&ui_radio($input_name, $davdefs{'dav'},
			[ [ "", $text{'default'} ],
			  [ 1, $text{'yes'} ],
			  [ 0, $text{'no'} ] ]));
	}
}

# mailbox_defaults_parse(&defs, &domain, &in)
# Parses the inputs created by mailbox_defaults_inputs, and updates a config
# file internal to this module to store them
sub mailbox_defaults_parse
{
local ($defs, $dom, $in) = @_;
if ($dom->{$module_name}) {
	local %davdefs;
	&read_file("$module_config_directory/defaults.$dom->{'id'}",\%davdefs);
	$davdefs{'dav'} = $in->{$input_name};
	&write_file("$module_config_directory/defaults.$dom->{'id'}",\%davdefs);
	}
}

# feature_webmin(&domain)
# Returns a list of webmin module names and ACL hash references to be set for
# the Webmin user when this feature is enabled
sub feature_webmin
{
local @doms = map { $_->{'dom'} } grep { $_->{$module_name} } @{$_[1]};
if (@doms) {
	return ( [ $module_name,
		   { 'dom' => join(" ", @doms),
		     'noconfig' => 1 } ] );
	}
else {
	return ( );
	}
}

# feature_links(&dom)
# Returns a link to the DAV module for this domain
sub feature_links
{
local ($dom) = @_;
return ( { 'mod' => $module_name,
	   'page' => "index.cgi?dom=$dom->{'id'}",
	   'desc' => $text{'index_desc'},
	   'cat' => 'services',
         },
	 { 'mod' => $module_name,
	   'page' => "list_shares.cgi?dom=$dom->{'id'}",
	   'desc' => $text{'shares_link'},
	   'cat' => 'services',
         },
       );
}

1;

