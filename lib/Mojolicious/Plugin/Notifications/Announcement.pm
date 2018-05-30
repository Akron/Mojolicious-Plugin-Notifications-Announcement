package Mojolicious::Plugin::Notifications::Announcement;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util qw/b64_encode sha1_sum trim/;
use Mojo::ByteStream 'b';

# TODO:
#   - 'confirm'
#     click on 'ok' or 'cancel'
#   - 'seen'
#     requires the announcement to be displayed
#     to the user (ensured via JS) and then POSTed to the confirmation endpoint

# -> How can this be done? A javascript needs to send a POST
#    to the confirmation route


# Register the plugin
sub register {
  my ($plugin, $app, $anns) = @_;

  $anns ||= [];

  # Load parameter from Config file
  if (my $config_anns = $app->config('Notifications-Announcement')) {
    push @$anns, @$config_anns;
  };

  # Get helpers object
  my $helpers = $app->renderer->helpers;

  # Load Util-Callback and Notifications if not already loaded
  $app->plugin('Util::Callback') unless exists $helpers->{'callback'};
  $app->plugin('Notifications') unless exists $helpers->{'notify'};

  # Create a short hash based id for the announcement, if not yet defined
  for (my $i = 0; $i < @$anns; $i++) {
    my $ann = $anns->[$i];

    # No message given - remove
    unless ($ann->{msg}) {
      splice @$anns, $i, 0;
      $i--;
      next;
    };

    # Ignore announcement if it already has an identifier
    next if $ann->{id};

    my $str = '';

    # Stringify hash
    foreach my $key (sort keys %$ann) {
      $str .= b64_encode($key) . '~' . b64_encode($ann->{$key} // '') . '~';
    };

    # Add hash based id to announcement
    $ann->{id} = sha1_sum($str);
  };


  # Use notifications hook to add notification
  $app->hook(
    before_notifications => sub {
      my $c = shift;

      # Iterate over all announcements
      foreach my $ann (@$anns) {

        # Check if the announcement was already read
        next if $c->callback(
          check_announcement => $ann
        );

        # Render inline template
        my $msg = $c->include(inline => $ann->{msg});
        $msg = trim $msg if $msg;

        my $type = $ann->{type} // 'announce';

        # Send announcement
        $c->notify($type => $msg);

        # Set announcement to be read
        # TODO:
        #   This needs to be modified for 'confirm' type
        $c->callback(
          set_announcement => $ann
        );
      };
    }) if @$anns;
};


1;


__END__


Announcements are ensured to have valid C<id> and C<msg> information.
Further attributes can be set and will be passed to the callbacks.
