use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

plugin 'Notifications' => {
  HTML => 1
};

# Load on registration
plugin 'Notifications::Announcement' => [
  {
    id => 'ann-2018-05-24',
    msg => 'Please confirm!',
    type => 'confirm',
    ok_label => "<%= stash 'ok' %>",
    cancel_label => "<%= stash 'cancel' %>"
  }
];

# Example route
get '/' => sub {
  my $c = shift;
  return $c->render(
    inline => '%= notifications "html"',
    ok => 'fine!',
    cancel => 'later!'
  );
};

my $t = Test::Mojo->new;

# Take default route
$t->get_ok('/')
  ->status_is(200)
  ->content_like(qr!/announcements/confirm!)
  ->text_is('button.ok','fine!')
  ->text_is('button.cancel','later!')
  ;

done_testing;
__END__
