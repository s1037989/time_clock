use Mojolicious::Lite;

use lib '../Mojolicious-Plugin-OAuth2Accounts/lib';
use lib 'lib';

use Mojo::Pg;
use TimeClock::Model::OAuth2;
use TimeClock::Model::Timeclock;

my $config = plugin 'Config';

helper 'pg' => sub { state $pg = Mojo::Pg->new(shift->config('pg')) };
helper 'model.oauth2' => sub { state $users = TimeClock::Model::OAuth2->new(pg => shift->pg) };
helper 'model.timeclock' => sub { state $timeclock = TimeClock::Model::Timeclock->new(pg => shift->pg) };
app->sessions->default_expiration(86400*365*10);
app->pg->migrations->from_data->migrate;

plugin "OAuth2Accounts" => {
  on_logout => '/',
  on_success => 'timeclock',
  on_error => 'connect',
  on_connect => sub { shift->model->oauth2->store(@_) },
  providers => $config->{oauth2},
};

get '/' => sub {
  my $c = shift;
  $c->session('id') ? $c->redirect_to('timeclock') : $c->redirect_to('connect');
};

get "/connect" => sub {
  my $c = shift;
  $c->session('token' => {}) unless $c->session('token');
};

get '/profile' => sub {
  my $c = shift;
  $c->redirect_to('connect') unless $c->session('id');
  $c->stash(user => $c->model->oauth2->find($c->session('id')));
};

get '/admin' => sub {
  my $c = shift;
  $c->redirect_to('connect') unless $c->session('id');
  $c->stash(timeclock => $c->model->timeclock);
};

get '/timeclock' => sub {
  my $c = shift;
  $c->redirect_to('connect') unless $c->session('id');
  $c->stash(user => $c->model->oauth2->find($c->session('id')));
  $c->stash(timeclock => $c->model->timeclock);
};

post '/timeclock' => sub {
  my $c = shift;
  $c->redirect_to('connect') unless $c->session('id');
  if ( $c->param('clock') eq 'in' ) {
    $c->model->timeclock->clock_in($c->session('id'), $c->param('lat'), $c->param('lon'));
  } elsif ( $c->param('clock') eq 'out' ) {
    $c->model->timeclock->clock_out($c->session('id'), $c->param('lat'), $c->param('lon'));
  }
  $c->redirect_to('timeclock');
};

app->start;

__DATA__

@@ admin.html.ep
% foreach my $user ( @{$timeclock->users} ) {
  % my $status = $timeclock->status($user->{id});
  Name: <%= $timeclock->user($user->{id})->{first_name} %><br />
  Status: <%= $status ? "Active since $status->{time_in} from $status->{time_in_lat} $status->{time_in_lon}" : 'Not active' %><hr />
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
Lat: <div id="div_lat"></div>
Lon: <div id="div_lon"></div>
%= form_for timeclock => begin
%= hidden_field 'lat' => '', id => 'lat'
%= hidden_field 'lon' => '', id => 'lon'
% if ( my $status = $timeclock->status(session 'id') ) {
  <%= $status->{time_in} %><br />
  %= hidden_field clock => 'out'
  %= submit_button 'Clock out'
% } else {
  Not active <br />
  %= hidden_field clock => 'in'
  %= submit_button 'Clock in'
% }
% end

@@ connect.html.ep
% if ( my $error = flash 'error' ) {
  <h3><%= $error %></h3>
% }
<p>Please login by connecting with one of the following authentication providers.  Each will ask for only your basic information so that we can copy this information into our database and create a passwordless user account for you.</p>
<%= defined session('token')->{facebook} ? 'Re-connect' : 'Connect' %> with <%= link_to 'Facebook' => 'connectprovider', {provider => 'facebook'} %><br />
<%= defined session('token')->{twitter} ? 'Re-connect' : 'Connect' %> with <%= link_to 'Twitter' => 'connectprovider', {provider => 'twitter'} %><br />
<%= defined session('token')->{google} ? 'Re-connect' : 'Connect' %> with <%= link_to 'Google' => 'connectprovider', {provider => 'google'} %><br />
<%= defined session('token')->{mocked} ? 'Re-connect' : 'Connect' %> with <%= link_to 'Mocked' => 'connectprovider', {provider => 'mocked'} %><br />
<%= link_to "Connect!", $c->oauth2->auth_url("facebook", scope => "user_about_me email") %><br />
<p><%= link_to Logout => 'logout' %></p>

@@ profile.html.ep
Email: <%= $user->{email} %><br />
First Name: <%= $user->{first_name} %><br />
Last Name: <%= $user->{last_name} %><br />
<p><%= link_to Logout => 'logout' %></p>

@@ migrations
-- 1 up
create table if not exists users (
  id         text primary key,
  email      text,
  first_name text,
  last_name  text,
  created    timestamptz not null default now()
);
create table if not exists providers (
  id          text,
  provider_id text,
  provider    text,
  created     timestamptz not null default now(),
  PRIMARY KEY (id, provider_id, provider)
);
create table if not exists timeclock (
  id          serial primary key,
  user_id     text,
  time_in     timestamptz,
  time_out    timestamptz,
  time_in_lat text,
  time_in_lon text,
  time_out_lat text,
  time_out_lon text
);

-- 1 down
drop table if exists providers;
drop table if exists users;
drop table if exists timeclock;
