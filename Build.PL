use strict;
use Module::Build;

my $class;

my $build = $class->new(
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

$build->{config}{__template_path} = '/usr/local/mariachi';

$build->create_build_script;

BEGIN {
    $class = Module::Build->subclass(
        class => 'My::Build',
        code  => <<'CODE' );
    use File::Find;

    sub ACTION_install {
        my $self = shift;
        $self->SUPER::ACTION_install;
        local $::FAKE;
        $self->ACTION_install_templates;
    }

    sub ACTION_fakeinstall {
        my $self = shift;
        $self->SUPER::ACTION_fakeinstall;
        local $::FAKE = 1;
        $self->ACTION_install_templates;
    }

    sub _find_templates {
        my $class;
        my @files;
        find(sub {
                 $File::Find::prune = 1 if -d && /^\.svn/;
                 return if -d;
                 return if /~$/;
                 push @files, $File::Find::name;
             }, 'templates');
        return @files;
    }

    sub ACTION_install_templates {
        my $self = shift;
        my $path = $self->{config}{__template_path};
        my @files = $self->_find_templates;
        print "installing templates to $path";
        for (@files) {
            if ($::FAKE) {
                print "$_ -> $path/$_ (FAKE)\n";
            }
            else {
                $self->copy_if_modified($_, $path);
            }
        }
    }

CODE
}
