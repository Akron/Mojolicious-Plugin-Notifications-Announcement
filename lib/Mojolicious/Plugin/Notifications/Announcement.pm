package Mojolicious::Plugin::Notifications::Announcement;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util qw/b64_encode sha1_sum trim/;
use Mojo::ByteStream 'b';

our $VERSION = '0.02';

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
        # DEPRECATED!
        $c->callback(
          set_announcement => $ann
        );

        # Hook for caching
        $c->app->plugins->emit_hook(
          after_announcement => ($c, $ann)
        );
      };
    }) if @$anns;
};


1;


__END__

=pod

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Notifications::Announcement - Frontend Service Announcements


=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('Notifications::Announcement' => [
    {
      msg => 'We have a new feature, <%= stash 'user_name' %>!'
    },
    {
      msg => 'We have updated our privacy policy!'
    }
  ]);

  # Mojolicious::Lite
  plugin 'Notifications::Announcement';


=head1 DESCRIPTION

L<Mojolicious::Plugin::Notifications::Announcement> uses
L<Mojolicious::Plugin::Notifications> to present service announcements
to users.

=head1 METHODS

=head2 register

  # Mojolicious
  $app->plugin('Notifications::Announcement' => [
    {
      msg => 'We have a new feature, <%= stash 'user_name' %>!'
    },
    {
      msg => 'We have updated our privacy policy!',
      id => 'abcde054321'
    }
  ]);

Called when registering the plugin.

Accepts an optional array of announcements, that at least require a C<msg>
field, that is treated as an inline L<Mojo::Template>.

Announcements can be set as part of the configuration
file with the key C<Notifications-Announcement> or on registration
(that will be merged with the announcement list from the configuration).

Announcements are ensured to have a valid C<id> information as well.
If not set, it will be added as a checksum of all announcement attributes.
Further attributes can be set and will be passed to the callbacks.


=head1 CALLBACKS

=head2 check_announcement

  app->callback(
    check_announcement => sub {
      my ($c, $ann) = @_;
      return 1 if $c->session('n!' . $ann->{id});
      return;
    });

This callback is released to check if an announcement should
be received or not. Expects a positive
return value, if the announcement should not be received,
otherwise it's send.
Passes the current controller and the announcement object
with all parameters, at least C<msg> and C<id>.

=head1 HOOKS

=head2 after_announcement

  app->hook(
    after_announcement => sub {
      my ($c, $ann) = @_;
      $c->session('n!' . $ann->{id} => 1);
    });

This hook is run after an announcement was served.
Passes the current controller and the announcement object
with all parameters, at least C<msg> and C<id>.


=head1 DEPENDENCIES

L<Mojolicious>, L<Mojolicious::Plugin::Util::Callback>,
L<Mojolicious::Plugin::Notifications>.


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Notifications-Announcement


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2018, L<Nils Diewald|https://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

=cut
