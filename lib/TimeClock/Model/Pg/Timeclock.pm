package TimeClock::Model::Pg::Timeclock;
use Mojo::Base 'TimeClock::Model::Pg';

use Math::Round 'nearest';
use DateTime::Format::Pg;
use DateTime::Format::Duration;

sub status {
  my $self = shift;
  my $status = $self->pg->db->query('select *, round_duration(time_in, time_out) as duration from timeclock where user_id = ? order by time_in desc limit 1', shift)->hash;
  return undef if $status->{time_out};
  $status->{time_in} = DateTime::Format::Pg->parse_timestamptz($status->{time_in});
  $status->{duration} = DateTime::Format::Pg->parse_duration($status->{duration});
  return $status;
}

sub duration {
  my ($self, $duration) = @_;
  #my $d = DateTime::Format::Human::Duration->new();
  #$d->format_duration($duration, units => [qw/hours minutes/]);
  my $d = DateTime::Format::Duration->new();
    my @units = qw/hours minutes/;
    my @duration_vals = $duration->in_units( @units ); 
    my $i = 0;
    my %duration_vals = map { ($_ => $duration_vals[$i++]) } @units;
    my %positive_duration_vals = map { ($_ => abs $duration_vals{$_}) } keys %duration_vals;
    return join ':', map { $_ < 10 ? "0$_" : $_ } DateTime::Duration->new(%positive_duration_vals)->in_units(@units);
}

sub history {
  my $self = shift;
  my $r = $self->pg->db->query('select *, date_trunc(\'week\', time_in) as week, EXTRACT(DOW FROM time_in) as dow, round_duration(time_in, time_out) as duration from timeclock where user_id = ? order by week,dow,time_in', shift)->hashes;
  my $history = {};
  foreach ( @$r ) {
    $_->{week} = DateTime::Format::Pg->parse_timestamptz($_->{week})->ymd;
    $_->{time_in} = DateTime::Format::Pg->parse_timestamptz($_->{time_in});
    $_->{time_out} = $_->{time_out} ? DateTime::Format::Pg->parse_timestamptz($_->{time_out}) : undef;
    $_->{duration} = DateTime::Format::Pg->parse_duration($_->{duration});
    push @{$history->{$_->{week}}->{$_->{dow}}}, $_;
  }
  $history;
}

sub pay {
  my $self = shift;
  my $ids = join ',', split //, ('?' x ($#_+1));
  $self->pg->db->query("update timeclock set paid=1,time_out=case when time_out is null then now() else time_out end where id in ($ids)", @_);
}

sub clock_in { shift->pg->db->query('insert into timeclock (user_id, time_in, time_in_lat, time_in_lon) values (?, now(), ?, ?) returning id', @_) }

sub clock_out { shift->pg->db->query('update timeclock set time_out = now(), time_out_lat = ?, time_out_lon = ? where user_id = ? and time_out is null', @_[1,2], $_[0]) }

sub users { shift->pg->db->query('select id from users')->hashes }

sub user { shift->pg->db->query('select * from users where id = ?', shift)->hash }

1;

__DATA__

@@ migrations
-- 1 up
create table if not exists timeclock (
  id          serial primary key,
  user_id     text,
  time_in     timestamptz,
  time_out    timestamptz,
  time_in_lat text,
  time_in_lon text,
  time_out_lat text,
  time_out_lon text,
  paid        integer
);
CREATE OR REPLACE FUNCTION round_duration(TIMESTAMPTZ, TIMESTAMPTZ) 
RETURNS INTERVAL AS $$ 
  SELECT date_trunc('hour', age(case when $2 is not null then $2 else now() end, $1)) + INTERVAL '15 min' * ROUND(date_part('minute', age(case when $2 is not null then $2 else now() end, $1)) / 15.0) 
$$ LANGUAGE SQL;

-- 1 down
drop table if exists timeclock;
