use strict;
use lib qw(inc);
use Siesta::Build;

my $build = Siesta::Build->new(
    module_name  => "Mariachi",
    dynamic_config => 1,
    license      => 'perl',
    script_files => [ 'mariachi' ],
    requires     => {
        'AppConfig'       => '1.55',
        'Email::Folder'   => '0.5',
        'Module::Build'   => '0.18',
        'Mail::Thread'    => '2.2',
        'Mail::Thread::Chronological' => '1.22',
        'Email::Thread'   => 0,
        'Template'        => 0,
        'Template::Plugin::Page' => 0,
        'Date::Parse'     => 0,
        'Class::Accessor' => 0,
        'Email::Find'     => 0,
        'Memoize'         => 0,
        'URI::Find::Schemeless::Stricter' => 0,
        'Test::More'      => 0,
        'Storable'        => 0,
        'Time::HiRes'     => 0,
        'File::Find::Rule' => 0,
        'File::Path'      => 0,
        'File::Copy'      => 0,
        'File::Basename'  => 0,
    },
    sign => 1,
    create_makefile_pl => 'passthrough',
   );

warn "we currently install templates into /usr/local/mariachi/templates.  this will be customizable in a future release\n";
$build->{config}{__extras_destination} = '/usr/local/mariachi';
$build->{config}{__extras_from} = ['templates'];

$build->create_build_script;
