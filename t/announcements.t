use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

plugin 'Notifications' => {
  JSON => 1
};

# Load from config
plugin Config => {
  default => {
    'Notifications-Announcement' => [
      {
        msg => 'Dear user, first'
      }
    ]
  }
};


# Load on registration
plugin 'Notifications::Announcement' => [
  {
    id => 'ann-2018-05-24',
    msg => 'Dear <%= stash "user" %>, we want to inform you ...',
    type => 'info' # Notification type
  }
];


# Set some stash values
app->defaults(
  user => 'Akron'
);


# Establish check callback
app->callback(
  check_announcement => sub {
    my ($c, $ann) = @_;
    return 1 if $c->session('n!' . $ann->{id});
    return;
  });

app->hook(
  after_announcement => sub {
    my ($c, $ann) = @_;
    $c->session('n!' . $ann->{id} => 1);
    return;
  });


# Example route
get '/' => sub {
  my $c = shift;
  return $c->render(json => $c->notifications(json => { 'msg' => 'Hello!'}));
};


my $t = Test::Mojo->new;

# First call with announcements
$t->get_ok('/')
  ->json_is('/msg', 'Hello!')
  ->json_is('/notifications/0/0', 'info')
  ->json_is('/notifications/0/1', 'Dear Akron, we want to inform you ...')
  ->json_is('/notifications/1/0', 'announce')
  ->json_is('/notifications/1/1', 'Dear user, first')
  ;

# Second call without announcements
$t->get_ok('/')
  ->json_is('/msg', 'Hello!')
  ->json_hasnt('/notifications')
  ;



done_testing;
__END__
