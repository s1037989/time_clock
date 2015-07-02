package TimeClock::Model::Timeclock;
use Mojo::Base -base;

use UUID::Tiny ':std';

has 'pg';

sub status {
  my $self = shift;
  my $status = $self->pg->db->query('select * from timeclock where user_id = ? order by time_in desc limit 1', shift)->hash;
  return $status->{time_out} ? undef : $status;
}

sub clock_in { shift->pg->db->query('insert into timeclock (user_id, time_in, time_in_lat, time_in_lon) values (?, now(), ?, ?) returning id', @_) }

sub clock_out { shift->pg->db->query('update timeclock set time_out = now(), time_out_lat = ?, time_out_lon = ? where user_id = ? and time_out is null', @_[1,2], $_[0]) }

sub users { shift->pg->db->query('select id from users')->hashes }

sub user { shift->pg->db->query('select first_name from users where id = ?', shift)->hash }

1;
