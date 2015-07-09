package TimeClock::Model::Pg::Users;
use Mojo::Base 'TimeClock::Model::Pg';

use UUID::Tiny ':std';

sub store {
  my $self = shift;
  if ( $#_ == 1 ) {
    my ($id, $provider) = @_;
    my $r = $self->pg->db->query('select id from providers where id = ? and provider = ?', $id, $provider)->hash;
    ref $r ? $r->{id} : undef;
  } elsif ( $#_ > 1 ) {
    my ($id, $provider, $json, $mapped) = @_;
    unless ( $self->pg->db->query('select id from users where id = ?', $id)->rows ) {
      $self->pg->db->query('insert into users (id, email, first_name, last_name) values (?, ?, ?, ?)', $id, $mapped->{email}, $mapped->{first_name}, $mapped->{last_name});
    }
    unless ( $self->pg->db->query('select id from providers where provider_id = ?', $mapped->{id})->rows ) {
      $self->pg->db->query('insert into providers (id, provider_id, provider) values (?, ?, ?)', $id, $mapped->{id}, $provider);
    }
  } else {
    my ($provider_id) = @_;
    my $r = $self->pg->db->query('select id from providers where provider_id = ?', $provider_id)->hash;
    ref $r ? $r->{id} : uuid_to_string(create_uuid(UUID_V4));
  }
}

sub find { shift->pg->db->query('select * from users where id = ?', shift)->hash }

1;

__DATA__

@@ migrations
-- 1 up
create table if not exists users (
  id         text primary key,
  email      text,
  first_name text,
  last_name  text,
  admin      integer,
  created    timestamptz not null default now()
);
create table if not exists providers (
  id          text,
  provider_id text,
  provider    text,
  created     timestamptz not null default now(),
  PRIMARY KEY (id, provider_id, provider)
);

-- 1 down
drop table if exists providers;
drop table if exists users;
