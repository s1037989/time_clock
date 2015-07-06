use Mojolicious::Lite;

use lib '../Mojolicious-Plugin-OAuth2-Fetch/lib';
use lib 'lib';

use Mojo::Pg;
use TimeClock::Model::Pg::Users;
use TimeClock::Model::Pg::Timeclock;

my $config = plugin 'Config';

plugin "OAuth2::Fetch" => {
  on_success => 'timeclock',
  on_error => 'connect',
  on_connect => sub { shift->model->users->store(@_) },
  on_disconnect => '/',
  default_provider => 'facebook',
  providers => $config->{oauth2},
};

helper 'pg' => sub { state $pg = Mojo::Pg->new(shift->config('pg')) };
helper 'model.users' => sub { state $users = TimeClock::Model::Pg::Users->new(pg => shift->pg) };
helper 'model.timeclock' => sub { state $timeclock = TimeClock::Model::Pg::Timeclock->new(pg => shift->pg) };

app->sessions->default_expiration(86400*365*10);
app->model->users->migrate;
app->model->timeclock->migrate;

get '/' => sub {
  my $c = shift;
  $c->session('oauth2.id') ? $c->redirect_to('timeclock') : $c->redirect_to('connectprovider', {provider => 'facebook'});
};

get '/status' => sub {
  my $c = shift;
  $c->redirect_to('connect') unless $c->session('oauth2.id');
  $c->stash(timeclock => $c->model->timeclock);
};

get '/history/:user' => {user => ''} => sub {
  my $c = shift;
  $c->redirect_to('connect') unless $c->session('oauth2.id');
  $c->stash(user => $c->param('user'));
  $c->stash(timeclock => $c->model->timeclock);
};

get '/pay/:user/:ids' => sub {
  my $c = shift;
  $c->redirect_to('connect') unless $c->session('oauth2.id');
  $c->model->timeclock->pay(split /,/, $c->param('ids'));
  $c->stash(user => $c->param('user'));
  $c->stash(timeclock => $c->model->timeclock);
  $c->redirect_to('historyuser', {user => $c->param('user')});
} => 'payuser';

get '/timeclock' => sub {
  my $c = shift;
  $c->redirect_to('connect') unless $c->session('oauth2.id');
  $c->stash(user => $c->model->timeclock->user($c->session('oauth2.id')));
  $c->stash(timeclock => $c->model->timeclock);
};

post '/timeclock' => sub {
  my $c = shift;
  $c->redirect_to('connect') unless $c->session('oauth2.id');
  if ( $c->param('clock') eq 'in' ) {
    $c->model->timeclock->clock_in($c->session('oauth2.id'), $c->param('lat'), $c->param('lon'));
  } elsif ( $c->param('clock') eq 'out' ) {
    $c->model->timeclock->clock_out($c->session('oauth2.id'), $c->param('lat'), $c->param('lon'));
  }
  $c->redirect_to('timeclock');
};

app->start;

__DATA__

@@ historyuser.html.ep
% my $week;
<%= link_to "All user status" => 'status' %><hr />
<%= $timeclock->user($user)->{first_name} %><br />
<table>
  <tr><th>week</th><th>Sunday</th><th>Monday</th><th>Tuesday</th><th>Wednesday</th><th>Thursday</th><th>Friday</th><th>Saturday</th><th>Total</th></tr>
% my $history = $timeclock->history($user);
% foreach my $week ( sort { $b cmp $a } keys %$history ) {
  <tr>
  <td><%= $week %>
  % my $week_time;
  % my $unpaid;
  % my @unpaid;
  % foreach my $dow ( qw/0 1 2 3 4 5 6/ ) {
    <td>
    % my $day_time;
    % foreach my $e ( @{$history->{$week}->{$dow}} ) {
      % $day_time = $day_time ? $day_time->add_duration($e->{duration}->clone) : $e->{duration}->clone;
      % $week_time = $week_time ? $week_time->add_duration($e->{duration}->clone) : $e->{duration}->clone;
      % $unpaid = $unpaid ? $unpaid->add_duration($e->{duration}->clone) : $e->{duration}->clone unless $e->{paid};
      % push @unpaid, $e->{id} if !$e->{paid};
      <%= link_to($e->{time_in}->hms => "https://www.google.com/maps/place//\@$e->{time_in_lat},$e->{time_in_lon},17z/data=!3m1!4b1!4m2!3m1!1s0x0:0x0") %> - <%= $e->{time_out} ? link_to($e->{time_out}->hms => "https://www.google.com/maps/place//\@$e->{time_in_lat},$e->{time_in_lon},17z/data=!3m1!4b1!4m2!3m1!1s0x0:0x0") : 'Active' %> (<%= $e->{paid} ? $timeclock->duration($e->{duration}) : link_to $timeclock->duration($e->{duration}) => 'payuser', {user => $user, ids => $e->{id}} %>)<br />
    % }
    % if ( $day_time ) {
      <b><%= $timeclock->duration($day_time) %></b>
    % }
    </td>
  % }
  <td>
  % if ( $unpaid ) {
    <b><%= link_to $timeclock->duration($unpaid, 1) => 'payuser', {user => $user, ids => join(',', @unpaid)} %></b><br />
  % }
  % if ( $week_time ) {
    <b><%= $timeclock->duration($week_time, 1) %></b><br />
  % }
  </td>
  </tr>
% }
</table>

@@ status.html.ep
(I am <%= session 'oauth2.id' %>)<br />
% foreach my $user ( @{$timeclock->users} ) {
  % my $status = $timeclock->status($user->{id});
  Name: <%= link_to $timeclock->user($user->{id})->{first_name} => 'historyuser', {user => $user->{id}} %><br />
  Status: <%== $status ? "Active since ".link_to($status->{time_in}->datetime => "https://www.google.com/maps/place//\@$status->{time_in_lat},$status->{time_in_lon},17z/data=!3m1!4b1!4m2!3m1!1s0x0:0x0")." (".$timeclock->duration($status->{duration}).")" : 'Not active' %><hr />
% }

@@ timeclock.html.ep
<script src="http://maps.googleapis.com/maps/api/js?key=AIzaSyDKw1I9ZlI-piCBp2zXSuviBDVRjju-aYI&sensor=true&libraries=adsense"></script>
<script src="http://ctrlq.org/common/js/jquery.min.js"></script>   
<script>
  if ( "geolocation" in navigator ) {
    navigator.geolocation.getCurrentPosition(function(position){
      var lat = position.coords.latitude.toFixed(5);
      var lon = position.coords.longitude.toFixed(5);
      console.log(lat, lon);
      $('#lat').attr('value', lat);
      $('#lon').attr('value', lon);
      $('#div_lat').text(lat);
      $('#div_lon').text(lon);
    }, null, {enableHighAccuracy: true, timeout: 5000, maximumAge: 1000});
  }
</script>
Name: <%= $user->{first_name} %><br />
%= form_for timeclock => begin
%= hidden_field 'lat' => '', id => 'lat'
%= hidden_field 'lon' => '', id => 'lon'
% if ( my $status = $timeclock->status(session 'oauth2.id') ) {
%#  <%= $status->{time_in} %>(<%= $timeclock->duration($status->{duration}) %>)<br />
  %= hidden_field clock => 'out'
  %= submit_button 'Clock out'
% } else {
  Not active <br />
  %= hidden_field clock => 'in'
  %= submit_button 'Clock in'
% }
% end
