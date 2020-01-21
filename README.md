check_mtr
=========

Use [My traceroute(MTR)](https://github.com/traviscross/mtr) to monitor all reachable routers on the network path.

Requirements
------------

**General**

- Perl 5
- Perl Modules:
    - Monitoring::Plugin or Nagios::Plugin
- [mtr](https://github.com/traviscross/mtr)

**RHEL/CentOS**

- perl
- perl-Monitoring-Plugin or perl-Nagios-Plugin
- mtr


Installation
------------

Just copy the file `check_mtr.pl` to your Icinga or Nagios plugin directory.

Source
------

- [Latest source at git.dinotools.org](https://git.dinotools.org/monitoring/check_mtr)
- [Mirror at github.com](https://github.com/DinoTools/monitoring-check_mtr)

License
-------

GPLv3+
