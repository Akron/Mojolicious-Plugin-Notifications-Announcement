use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Mojolicious::Plugin::Notifications::Announcement',
  VERSION_FROM => 'lib/Mojolicious/Plugin/Notifications/Announcement.pm',
  ABSTRACT     => 'Frontend Service Announcements',
  AUTHOR       => 'Nils Diewald',
  BUILD_REQUIRES => {
    'Test::More' => 0
  },
  PREREQ_PM    => {
    'Mojolicious' => '7.79',
    'Mojolicious::Plugin::Util::Callback' => '0.05',
    'Mojolicious::Plugin::Notifications' => '1.02'
  },
  META_MERGE   => {
    requires  => {
      perl => '5.010001'
    },
    resources => {
      license     => 'http://www.opensource.org/licenses/artistic-license-2.0',
      repository  => 'https://github.com/Akron/Mojolicious-Plugin-Notifications->Announcement'
    }
  },
  LICENSE      => 'artistic_2',
  MIN_PERL_VERSION => '5.010001',
  test         => {
    TESTS => 't/*.t'
  }
);
