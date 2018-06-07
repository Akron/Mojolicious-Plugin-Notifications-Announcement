package Mojolicious::Plugin::Notifications::Announcement;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util qw/b64_encode sha1_sum trim/;
use Mojo::ByteStream 'b';
use List::Util qw/none/;

our $VERSION = '0.03';

# TODO:
#   Enhance with CSRF token!

# TODO:
#   Accept ok, ok_label, cancel, cancel_label to override in
#   confirmation announcements. These however also needs to be templates to
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

  my ($ok_route, $cancel_route);

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

  # Predefine confirmation route as it is used twice
  my $confirmation_route = sub {
    my $c = shift;
    my $ann_id = $c->param('aid');

    # Method needs to be post
    if ($c->req->method ne 'POST') {

      # TODO: Correct error message
      $c->render(
        status => 200,
        text => 'Announcement confirmation requires POST'
      );
    };

    # Is the announcement confirmed or canceled
    my $confirmed = $c->stash('confirmed');

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
  };

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
      my $type = shift;

      # Check names
      if ($type ne 'ok' && $type ne 'cancel') {
        $app->log->error("Undefined route type for $route");
        return;
      };

      # Check methods
      if (none { $_ =~ m!^POST$!i } @{$r->via}) {
        $app->log->error("Route method for $route needs to support POST");
        return;
      };

      # Set name
      $r = $r->name($route . '_' . $type);

      # Treat confirmation
      if ($type eq 'ok') {
        # Define confirmation route
        $r->to(confirmed => 1, cb => $confirmation_route);
        $ok_route = 1;
      }

      # Treat cancellation
      elsif ($type eq 'cancel') {

        # Define cancelation route
        $r->to(confirmed => 0, cb => $confirmation_route);
        $cancel_route = 1;
      };
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

          # Get ok route
          $param{ok} = $c->url_for($route . '_ok')->query(aid => $ann->{id})->to_abs
            if $ok_route;

          # Get cancel route
          $param{cancel} = $c->url_for($route . '_cancel')->query(aid => $ann->{id})->to_abs
            if $cancel_route;

          # The confirmation routes are not defined
          if (!$param{ok} && !$param{cancel}) {
            $c->app->log->error('Confirmation routes undefined for ' . __PACKAGE__);
            return;
          };

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

  # Check if announcement was already read
  callback check_announcement => sub {
    my ($c, $ann) = @_;
    return 1 if $c->session('read-' . $ann->{id});
    return;
  };

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
  post('/confirm/ok')->announcements('ok');
  post('/confirm/cancel')->announcements('cancel');

Establish announcement routes for confirmation
and cancellation of announcements requiring confirmation.
Accepts the route type as a string parameter
(either C<ok> or C<cancel>).

The shortcut requires routes that accept the C<POST> method.


=head1 DEPENDENCIES

L<Mojolicious>, L<Mojolicious::Plugin::Util::Callback>,
L<Mojolicious::Plugin::Notifications>.


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Notifications-Announcement


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2018, L<Nils Diewald|https://nils-diewald.de/>.

L<Mojolicious::Plugin::Notifications::Announcement> is developed as
part of the [KorAP](http://korap.ids-mannheim.de/)
Corpus Analysis Platform at the
[Institute for the German Language (IDS)](http://ids-mannheim.de/),
member of the
[Leibniz-Gemeinschaft](http://www.leibniz-gemeinschaft.de/en/about-us/leibniz-competition/projekte-2011/2011-funding-line-2/).

This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

=cut
