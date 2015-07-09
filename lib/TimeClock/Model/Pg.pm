package TimeClock::Model::Pg;
use Mojo::Base -base;

use Mojo::Util 'decamelize';

has 'pg';

sub migrate { $_[0]->pg->migrations->from_data(ref($_[0]), 'migrations')->name(decamelize ref $_[0])->migrate }

1;
