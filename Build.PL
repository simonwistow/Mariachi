use strict;
use lib qw(../siesta/lib inc);
use Siesta::Build;

my $build = Siesta::Build->new(
    module_name  => "Mariachi",
    sign         => 1,
    license      => 'perl',
    script_files => [ 'mariachi' ],
    requires     => {
        'Email::Folder'   => 0,
        'Module::Build'   => '0.18',
        'Mail::Thread'    => '2.2',
        'Email::Thread'   => 0,
        'Template'        => 0,
        'Date::Parse'     => 0,
        'Class::Accessor' => 0,
        'Email::Find'     => 0,
        'URI::Find::Schemeless::Stricter' => 0,
    },
   );

$build->{config}{__extras_destination} = '/usr/local/mariachi';
$build->{config}{__extras_from} = ['templates'];

$build->create_build_script;
