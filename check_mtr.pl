#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use Pod::Text::Termcap;

use constant OK         => 0;
use constant WARNING    => 1;
use constant CRITICAL   => 2;
use constant UNKNOWN    => 3;
use constant DEPENDENT  => 4;

my $pkg_nagios_available = 0;
my $pkg_monitoring_available = 0;
my @g_long_message;

BEGIN {
    eval {
        require Monitoring::Plugin;
        require Monitoring::Plugin::Functions;
        $pkg_monitoring_available = 1;
    };
    if (!$pkg_monitoring_available) {
        eval {
            require Nagios::Plugin;
            require Nagios::Plugin::Functions;
            *Monitoring::Plugin:: = *Nagios::Plugin::;
            $pkg_nagios_available = 1;
        };
    }
    if (!$pkg_monitoring_available && !$pkg_nagios_available) {
        print("UNKNOWN - Unable to find module Monitoring::Plugin or Nagios::Plugin\n");
        exit UNKNOWN;
    }
}

my $parser = Pod::Text::Termcap->new (sentence => 0, width => 78);
my $extra_doc = <<'END_MESSAGE';

END_MESSAGE

my $extra_doc_output;
$parser->output_string(\$extra_doc_output);
$parser->parse_string_document($extra_doc);

my $mp = Monitoring::Plugin->new(
    shortname => "check_mtr",
    usage => "",
    extra => $extra_doc_output
);

$mp->add_arg(
    spec => 'hostname|H=s',
    help => '',
    required => 1
);

$mp->add_arg(
    spec => 'latency-warn=s',
    help => '',

);

$mp->add_arg(
    spec => 'latency-crit=s',
    help => '',
);

$mp->add_arg(
    spec => 'packet-loss-warn=s',
    help => '',
);

$mp->add_arg(
    spec => 'packet-loss-crit=s',
    help => '',
);

$mp->add_arg(
    spec => 'tcp',
    help => 'Use TCP instead of ICMP Echo. (Default port: 443)',
);

$mp->add_arg(
    spec => 'udp',
    help => 'Use UDP instead of ICMP Echo. (Default port: 53)',
);

$mp->add_arg(
    spec => 'port=i',
    help => 'Use the specified port. Only aplicable if TCP or UDP set.'
);

$mp->add_arg(
    spec    => 'cycles=i',
    help    => 'Number of cycles to check hosts and the reliability. (Default: 4)',
    default => 4,
);

$mp->add_arg(
    spec => 'dns',
    help => 'Try to resolve the hostnames of the hops.',
);

$mp->getopts;

check();

my ($code, $message) = $mp->check_messages();
wrap_exit($code, $message . "\n" . join("\n", @g_long_message));

sub check
{
    my @cmd;
    push(@cmd, 'mtr');
    push(@cmd, ('--report', '--report-wide'));
    push(@cmd, ('--report-cycles', $mp->opts->cycles));
    if ($mp->opts->dns) {
        push(@cmd, '--show-ip');
    } else {
        push(@cmd, '--no-dns');
    }
    if ($mp->opts->tcp && $mp->opts->udp) {
        wrap_exit(UNKNOWN, 'TCP and UDP mode can not be used in combination');
    } elsif ($mp->opts->tcp) {
        push(@cmd, '--tcp');
        my $port = $mp->opts->port;
        if (!defined $port) {
            $port = 443;
        }
        push(@cmd, ('--port', $port));
    } elsif ($mp->opts->udp) {
        push(@cmd, '--udp');
        my $port = $mp->opts->port;
        if (!defined $port) {
            $port = 53;
        }
        push(@cmd, ('--port', $port));
    }
    push(@cmd, $mp->opts->hostname);

    open(my $pipe,'-|',@cmd) or die "Can't start process: $!";
    my @output=<$pipe>;
    close($pipe) or die "Broken pipe: $!";
    my $hop_count = 0;
    my $hop_reachable = 1;

    # Heading in the long output
    push(@g_long_message, "Hops:");
    foreach my $line (@output) {
        my $status = OK;
        if ($line =~ /^\s*(\d+).\s*[|-]+?\s+(([0-9a-f.:\?]+)|(\S+)\s+\(([0-9a-f.:\?]+)\))\s+(\d+.\d+)%?\s+(\d+)\s+(\d+.\d+)\s+(\d+.\d+)\s+(.*?)\s.*?$/) {
            my $host_address = $2;
            my $latency_value = $9;
            my $packet_loss_value = $6;
            my $latency_status = OK;
            my $packet_loss_status = OK;

            $hop_count++;

            if ($host_address eq '???') {
                $hop_reachable = 0;
            } else {
                $hop_reachable = 1;
                $latency_status = $mp->check_threshold(
                    check    => $latency_value,
                    warning  => $mp->opts->get('latency-warn'),
                    critical => $mp->opts->get('latency-crit'),
                );
                $mp->add_perfdata(
                    label    => "hop_${hop_count}_rta",
                    value    => $latency_value,
                    warning  => $mp->opts->get('latency-warn'),
                    critical => $mp->opts->get('latency-crit'),
                );

                $packet_loss_status = $mp->check_threshold(
                    check    => $packet_loss_value,
                    warning  => $mp->opts->get('packet-loss-warn'),
                    critical => $mp->opts->get('packet-loss-crit'),
                );
                $mp->add_perfdata(
                    label    => "hop_${hop_count}_pl",
                    value    => $packet_loss_value,
                    warning  => $mp->opts->get('packet-loss-warn'),
                    critical => $mp->opts->get('packet-loss-crit'),
                );
            }

            if($latency_status != OK || $packet_loss_status != OK) {
                if ($latency_status > $packet_loss_status) {
                    $mp->add_message(
                        $latency_status,
                        sprintf(
                            '%s latency %s',
                            $host_address,
                            $latency_value
                        )
                    );
                    $status = $latency_status;
                } elsif ($latency_status < $packet_loss_status) {
                    $mp->add_message(
                        $packet_loss_status,
                        sprintf(
                            '%s packet loss %s%%',
                            $host_address,
                            $packet_loss_value
                        )
                    );
                    $status = $packet_loss_status;
                } else {
                    $mp->add_message(
                        $latency_status,
                        sprintf(
                            '%s latency %s and packet loss %s%%',
                            $host_address,
                            $latency_value,
                            $packet_loss_value
                        )
                    );
                    $status = $latency_status;
                }
            }
            my $status_msg = '';
            if ($status == OK) {
                $status_msg = '';
            } elsif ($status == WARNING) {
                $status_msg = ' <- !!! WARNING !!!';
            } elsif ($status == CRITICAL) {
                $status_msg = ' <- !!! CRITICAL !!!';
            } else {
                $status_msg = ' <- !!! Unknown !!!';
            }
            chomp($line);
            $line = $line =~ s/\|--//r;
            push(@g_long_message, $line.$status_msg);
        }
    }
    if (!$hop_reachable) {
        # Last hop is unreachable
        $mp->add_message(
            CRITICAL,
            sprintf(
                'Host %s unreachable',
                $mp->opts->hostname,
            )
        );
    } else {
        $mp->add_message(
            OK,
            sprintf(
                'Host %s reachable in %d hop(s)',
                $mp->opts->hostname,
                $hop_count,
            )
        );
    }
}

sub wrap_exit
{
    if($pkg_monitoring_available == 1) {
        $mp->plugin_exit( @_ );
    } else {
        $mp->nagios_exit( @_ );
    }
}
