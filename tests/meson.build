project(
    'installed-libpldm-consumers',
    ['c', 'cpp'],
    default_options: [
        'c_std=c17',
        'cpp_std=c++23',
        'warning_level=2',
        'werror=true',
    ],
)
if host_machine.system() == 'linux'
    add_project_arguments('-D_DEFAULT_SOURCE', language: 'c')
endif
c_dep = dependency('libpldm', static: true)
cpp_dep = dependency('libpldm++', static: true)
executable('consumer-c', 'consumer.c', dependencies: c_dep)
executable('consumer-cpp', 'consumer.cpp', dependencies: cpp_dep)
executable('fixture', 'fixture.c', dependencies: c_dep)
