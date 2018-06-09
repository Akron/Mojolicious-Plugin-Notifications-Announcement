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
    type => 'confirm'
  }
];

# Establish check callback
app->callback(
  check_announcement => sub {
    my ($c, $ann) = @_;
    return 1 if $c->session('n!' . $ann->{id});
    return;
  });

my (@cancel, @ok) = ();

hook after_announcement_ok => sub {
  my ($c, $ann) = @_;
  $c->session('n!' . $ann->{id} => 1);
  push @ok, $ann->{id};
  return;
};

hook after_announcement_cancel => sub {
  my ($c, $ann) = @_;
  push @cancel, 'cancelled ' . $ann->{id};
  return;
};

# Example route
get '/' => sub {
  my $c = shift;
  return $c->render(inline => '%= notifications "html"');
};

my $loglines = '';
app->log->on(
  message => sub {
    my ($log, $level, @lines) = @_;
    if ($level eq 'error') {
      $loglines = join ',', @lines;
    };
  });

my $t = Test::Mojo->new;

$t->get_ok('/')
  ->status_is(200)
  ->content_is("\n")
  ;

like($loglines, qr/undefined/);
$loglines = '';

get('/confirm')->announcements('ok');

like($loglines, qr/needs to support POST/);
$loglines = '';

post('/confirm')->announcements('ok');

ok(!$loglines);

my $action = $t->get_ok('/')
  ->status_is(200)
  ->text_is('div.notify-confirm', 'Please confirm!')
  ->text_is('div.notify-confirm form[method=post] button', 'OK')
  ->tx->res->dom->at('form')->attr('action');

like($action, qr!/confirm\?aid=ann-2018-05-24!, 'Path is correct');

is(scalar @ok, 0, 'No ok');
is(scalar @cancel, 0, 'No canceled');


# Get is not supported
$t->get_ok($action)
  ->status_is(404)
  ;

# Confirmation request still valid
my $csrf = $t->get_ok('/')
  ->status_is(200)
  ->text_is('div.notify-confirm', 'Please confirm!')
  ->text_is('div.notify-confirm form[method=post] button.ok', 'OK')
  ->element_exists_not('div.notify-confirm form[method=post] button.cancel')
  ->tx->res->dom('input[name=csrf_token]')->[0]->attr('value')
  ;

# Post is supported
$t->post_ok($action)
  ->status_is(400)
  ;

# Post is supported
$t->post_ok($action => form => { csrf_token => $csrf})
  ->status_is(200)
  ->content_is('Announcement confirmed')
  ;

is(scalar @ok, 1, '1 ok');
is($ok[0], 'ann-2018-05-24', '1 ok');
is(scalar @cancel, 0, 'No canceled');

# Notification is no longer needed
$t->get_ok('/')
  ->status_is(200)
  ->content_is("\n")
  ;


done_testing;

__END__
