package TimeClock::Model::Pg;
use Mojo::Base -base;

has 'pg';

sub migrate { shift->pg->migrations->from_data->migrate }

1;
