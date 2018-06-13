package Mojolicious::Plugin::Notifications::Announcement;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util qw/b64_encode sha1_sum trim/;
use Mojo::ByteStream 'b';
use List::Util qw/none/;

our $VERSION = '0.04';

# TODO:
#   Accept 'ok', 'ok_label', 'cancel', 'cancel_label',
#   'confirm' to override in confirmation announcements.

# TODO:
#   ok_labelThese however also needs to be templates to
#   support localization.

# TODO:
#   - 'seen'
#     requires the announcement to be displayed
#     to the user (ensured via JS) and then POSTed to the confirmation endpoint
#     -> How can this be done? A javascript needs to send a POST
#        to the confirmation route

# Register the plugin
sub register {
  my ($plugin, $app, $anns) = @_;

  $anns ||= [];

  my $conf_route;

  # Load parameter from Config file
  if (my $config_anns = $app->config('Notifications-Announcement')) {
    push @$anns, @$config_anns;
  };

  # Get helpers object
  my $helpers = $app->renderer->helpers;

  # Load Util-Callback and Notifications if not already loaded
  $app->plugin('Util::Callback') unless exists $helpers->{'callback'};
  $app->plugin('Notifications') unless exists $helpers->{'notify'};

  # This is a separate hash to access announcements by id
  my %ann_by_id;

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
    unless ($ann->{id}) {

      my $str = '';

      # Stringify hash
      foreach my $key (sort keys %$ann) {
        $str .= b64_encode($key) . '~' . b64_encode($ann->{$key} // '') . '~';
      };

      # Add hash based id to announcement
      $ann->{id} = sha1_sum($str);
    };

    # Remember the id
    $ann_by_id{$ann->{id}} = $ann;
  };


  # Add announcements shortcut
  my $route = 'announcements';
  $app->routes->add_shortcut(
    $route => sub {
      my $r = shift;

      # Check methods
      if (none { $_ =~ m!^POST$!i } @{$r->via}) {
        $app->log->error("Route method for $route needs to support POST");
        return;
      };

      # Set name
      $r = $r->name($route);

      # Define confirmation route
      $r->to(
        cb => sub {
          my $c = shift;
          my $v = $c->validation;
          $v->required('id');
          $v->required('a')->in(qw/ok cancel/);
          $v->csrf_protect;

          # TODO:
          #   Use respond_to
          # Method needs to be post
          if ($c->req->method ne 'POST') {
            return $c->render(
              status => 405,
              text => 'Confirmation needs to be POST request'
            );
          };

          # Check id or CSRF token
          if ($v->has_error('id') || $v->has_error('a')) {
            return $c->render(
              status => 400,
              text => 'Invalid announcement parameter passed'
            );
          };

          if ($v->has_error('csrf_token')) {
            return $c->render(
              status => 400,
              text => 'CSRF attack assumed'
            );
          };

          # Get annotation id
          my $ann_id = $v->param('id');

          # Is the announcement confirmed or canceled
          my $confirmed = $v->param('a') eq 'ok' ? 1 : 0;

          # Check for annotation based on id
          my $ann = $ann_by_id{$ann_id};

          # There is an annotation defined by that id ...
          if ($ann) {
            $c->app->plugins->emit_hook(
              'after_announcement_' . ($confirmed ? 'ok' : 'cancel') => ($c, $ann)
            );
          };

          # ... otherwise ignore!
          $c->render(
            status => 200,
            text => 'Announcement ' . ($confirmed ? 'confirmed' : 'canceled')
          );
        });
      $conf_route = 1;
    }
  );

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

        # Send an announcement that requires confirmation
        if ($type eq 'confirm') {
          my %param = ();

          my $r = $c->app->routes;

          # Check for confirmation route
          unless ($conf_route) {

            # Default confirmation path
            my $path = '/announcements/confirm';

            # The confirmation routes are not defined
            $c->app->log->info(
              'Create confirmation route under ' . $path
              );
            $r->post($path)->announcements;
            $conf_route = 1;
          };

          $param{ok} = $c->url_for($route)
            ->query(id => $ann->{id}, a => 'ok')->to_abs;

          # Get cancel route
          $param{cancel} = $c->url_for($route)
            ->query(id => $ann->{id}, a => 'cancel')->to_abs;

          # Send notification
          $c->notify($type => \%param => $msg);
        }

        # Send an announcement that requires no confirmation
        else {

          # Send announcement
          $c->notify($type => $msg);

          # Set announcement to be read

          # DEPRECATED!
          $c->callback(
            set_announcement => $ann
          );

          # DEPRECATED!
          $c->app->plugins->emit_hook(
            after_announcement => ($c, $ann)
          );

          # Immediately confirmed
          $c->app->plugins->emit_hook(
            after_announcement_ok => ($c, $ann)
          );
        };
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

  # In Mojolicious Lite
  plugin 'Notifications::Announcement' => [{
    msg => 'We have a new feature, <%= stash 'user_name' %>!'
  }];

  # Establish confirmation route
  post('/announce')->announcements;

  # Check if announcement was already read
  app->callback(check_announcement => sub {
    my ($c, $ann) = @_;
    return 1 if $c->session('read-' . $ann->{id});
    return;
  });

  # Confirm that the announcement was read
  hook after_announcement_ok => sub {
    my ($c, $ann) = @_;
    $c->session('read-' . $ann->{id} => 1);
  }

  # In templates
  %= notifications 'Alertify'

=head1 DESCRIPTION

L<Mojolicious::Plugin::Notifications::Announcement> uses
L<Mojolicious::Plugin::Notifications> to present service announcements
to users with specific requirements, e.g. confirmation or to be seen only once.

B<WARNING: This module is still in early development - don't use it for now!>


=head1 METHODS

=head2 register

  # Mojolicious
  $app->plugin('Notifications::Announcement' => [
    {
      msg => 'We have a new feature, <%= stash 'user_name' %>!'
    },
    {
      msg => 'We have updated our privacy policy!',
      type => 'confirm'
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
The C<type> attribute will be used as the notification type to
L<Mojolicious::Plugin::Notifications/notify> and defaults to C<announce>.

In case the type is C<confirm>, confirmation routes will be established.


=head1 CALLBACKS

=head2 check_announcement

  app->callback(
    check_announcement => sub {
      my ($c, $ann) = @_;
      return 1 if $c->session('n!' . $ann->{id});
      return;
    });

This callback is released to check if an announcement should
be served or not. Expects a positive
return value, if the announcement should not be served
(e.g. because it already was served to the user),
otherwise it is send.
Passes the current controller and the announcement object
with all parameters, at least C<msg> and C<id>.


=head1 HOOKS

=head2 after_announcement_ok

  app->hook(
    after_announcement_ok => sub {
      my ($c, $ann) = @_;
      $c->session('n!' . $ann->{id} => 1);
    });

This hook is run after an announcement was accepted,
that is either served or confirmed if required.
Passes the current controller and the announcement object
with all parameters, at least C<msg> and C<id>.


=head2 after_announcement_cancel

  app->hook(
    after_announcement_cancel => sub {
      my ($c, $ann) = @_;
      $c->session('n!' . $ann->{id} => 1);
    });

This hook is run after an announcement was canceled
in case confirmation is required.
Passes the current controller and the announcement object
with all parameters, at least C<msg> and C<id>.


=head1 SHORTCUT

=head2 announcements

  # In Mojolicious::Lite
  post('/confirm')->announcements;

Establish route for confirmation and cancellation of announcements
requiring confirmation.

The shortcut requires routes that accept the C<POST> method.

If no shortcut is defined, the default route is C</announcements/confirm>.


=head1 DEPENDENCIES

L<Mojolicious>, L<Mojolicious::Plugin::Util::Callback>,
L<Mojolicious::Plugin::Notifications>.


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Notifications-Announcement


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2018, L<Nils Diewald|https://nils-diewald.de/>.

L<Mojolicious::Plugin::Notifications::Announcement> is developed as
part of the L<KorAP|https://korap.ids-mannheim.de/>
Corpus Analysis Platform at the
L<Institute for the German Language (IDS)|http://ids-mannheim.de/>,
member of the
L<Leibniz Association|https://www.leibniz-gemeinschaft.de/en/home/>.



This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

=cut
