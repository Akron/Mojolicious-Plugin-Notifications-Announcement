package Mojolicious::Plugin::ServiceAnnouncements;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util qw/b64_encode sha1_sum trim/;
use Mojo::ByteStream 'b';


# TODO:
#   Introduce several announcement types
#   - 'show' (default)
#     requires the user to call announcement_for
#   - 'consent'
#     requires the user to click on a button
#   - 'seen'
#     requires the announcement to be displayed
#     to the user (ensured via JS)
#   There are additional parameters required
#   - times
#     Numerical value that needs to be stored
#     in the DB, times the announcement was
#     shown, seen or consented to
#   To target only some users, maybe a group,
#   an optional parameter may be
#   - for => sub {
#       my $c = shift;
#       return 1; # Return 1, if the user should be announced
#     }

# TODO:
#   Currently the mechanism focusses on registered
#   users but there should probably be a simple
#   cookie-based mechanism for every user as well!

# Compare to
#   - https://bitbucket.org/atlassianlabs/pas/wiki/Home?_ga=2.87742040.1973582524.1527180932-653801290.1527180932

# Register the plugin
sub register {
  my ($plugin, $app, $anns) = @_;

  $anns ||= [];

  # Load parameter from Config file
  if (my $config_anns = $app->config('ServiceAnnouncements')) {
    push @$anns, @$config_anns;
  };

  # Get helpers object
  my $helpers = $app->renderer->helpers;

  # Load Util-Callback if not already loaded
  foreach (qw/Callback/) {
    $app->plugin("Util::$_") unless exists $helpers->{ lc $_ };
  };

  # TODO:
  #   Use inline rendering

  # Create a hash based id for the announcement
  foreach my $ann (@$anns) {

    # Ignore announcement if it already has an identifier
    next if $ann->{id};

    my $str = '';

    # Stringify hash
    while (my ($key, $value) = each %$ann) {
      $str .= b64_encode($key) . '~' . b64_encode($value // '') . '~';
    };

    # Add hash based id to announcement
    $ann->{id} = sha1_sum($str);
  };

  # Set a db to keep track of all user id + announcement ids
  my $db = {};


  # This is a tag helper that will check, if the user needs a new announcement
  $app->helper(
    'announce_for' => sub {

      # No recent announcements set,
      # ignore
      return unless @$anns;

      my $c = shift;
      my $cb = ref $_[-1] eq 'CODE' ? pop : undef;

      # No callback defined
      return unless $cb;

      # Return if no user identifier is given
      my $user_id = shift or return;

      my $str = '';

      # Iterate over all announcements
      foreach my $ann (@$anns) {

        # No message given
        next unless $ann->{msg};

        # This will check the database, if the user
        # has already seen the announcement
        my $id = sha1_sum($user_id, $ann->{id});

        # Check if the announcement was already read
        next if $c->callback(
          check_service_announcement_for => $id
        );

        # Render inline template
        my $msg = $c->include(inline => $ann->{msg});
        $msg = trim $msg;

        # Render inline message
        $c->stash('announce.msg' => $msg);
        $c->stash('announce.id' => $ann->{id});
        $str .= $cb->();

        # Set announcement to be read
        # TODO:
        #   This needs to be modified for 'consent' types
        $c->callback(
          set_service_announcement_for => $id, 1
        );
      };

      return b($str);
    }
  );
};


1;


__END__

