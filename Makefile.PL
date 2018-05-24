use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Mojolicious::Plugin::ServiceAnnouncements',
  VERSION_FROM => 'lib/Mojolicious/Plugin/ServiceAnnouncements.pm',
  AUTHOR       => 'Nils Diewald',
  PREREQ_PM    => {
    'Mojolicious' => '7.79',
    'Mojolicious::Plugin::Util::Callback' => '0.05'
  },
  test         => {TESTS => 't/*.t'}
);
