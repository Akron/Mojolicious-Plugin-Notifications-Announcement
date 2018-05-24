use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

plugin 'ServiceAnnouncements' => [
  {
    id => 'ann-2018-05-24',
    msg => 'Dear <%= stash "user" %>, we want to inform you ...'
  },
  {
    msg => 'Dear user, first'
  }
];

app->defaults(
  user => 'Akron'
);

get '/' => sub {
  my $c = shift;
  $c->render(inline => <<TEMPLATE);
Here are announcements

<ul>
%= announce_for stash('user'), begin
  <li><%= stash 'announce.msg' %></li>
% end
</ul>
TEMPLATE
};


my %announcements = ();

# Set key
app->callback(
  check_service_announcement_for => sub {
    my ($c, $id) = @_;
    return $announcements{$id};
  }
);

# Set key
app->callback(
  set_service_announcement_for => sub {
    my ($c, $id, $value) = @_;
    return $announcements{$id} = $value;
  }
);


my $t = Test::Mojo->new;
$t->get_ok('/')
  ->status_is(200)
  ->content_like(qr/announcements/)
  ->text_like('ul > li:nth-of-type(1)', qr/Dear Akron, we want to inform/)
  ->text_like('ul > li:nth-of-type(2)', qr/Dear user, first/)
  ;

$t->get_ok('/')
  ->status_is(200)
  ->content_like(qr/announcements/)
  ->element_exists_not('ul > li')
  ;

done_testing();
