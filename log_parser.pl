# log_parser.pl
# Functions for parsing this module's logs
use strict;
use warnings;

do 'virtualmin-dav-lib.pl';

# parse_webmin_log(user, script, action, type, object, &params)
# Converts logged information from this module into human-readable form
sub parse_webmin_log
{
my ($user, $script, $action, $type, $object, $p) = @_;
if ($type eq "share") {
	return &text('log_'.$action.'_share',
		     "<tt>".&html_escape($object)."</tt>",
		     "<tt>".&html_escape($p->{'dom'})."</tt>");
	}
elsif ($type eq "auth") {
	return &text('log_auth', "<tt>".&html_escape($p->{'dom'})."</tt>");
	}
return undef;
}

