use strict;
use Module::Build;

Module::Build
  ->new( module_name  => "Mariachi",
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
                         },
         sign         => 1,
       )
  ->create_build_script;
