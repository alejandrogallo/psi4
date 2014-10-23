#!/usr/bin/env python
# vim:ft=python
#
# primitive frontend to cmake
# (c) Radovan Bast <radovan.bast@irsamc.ups-tlse.fr>
# (c) Jonas Juselius <jonas.juselius@uit.no>
# licensed under the GNU Lesser General Public License
# Ported to PSI4 by Roberto Di Remigio Oct. 2014
# based on initial work by Andy Simmonett (May 2013)

import os
import sys
import string
import re
import subprocess
import shutil

try:
    from argparse import ArgumentParser
except ImportError:
    print(
"""ERROR: Unable to import module "argparse" needed by this script. This
is probably because your Python interpreter (version %s) is older
than 2.7. While psi4 itself runs with >=2.6 at present, we may require
>=2.7 in future. You can:

(a) Upgrade python now to 2.7. Get the the python development libraries
    (provides "python-config") while you're at it. Then re-execute this
    script and continue with the psi4 build.

(b) Keep python 2.6 and install just the "argparse" module from
    https://pypi.python.org/pypi/argparse . Then re-execute this script
    and continue with the psi4 build.

(c) This script is just a wrapper that translates --with-option=VALUE
    specifications into cmake -DOPTION=VALUE style arguments, does some
    sanity checking, and defines common sets of options (e.g., --with-opt).
    It does not peer into your computer's libraries or compilers. So, you
    are welcome to skip this script and call "cmake" directly. Or, you
    can run this script with the options you want on a computer with
    python >=2.7, note the options passed to "cmake" and use those to
    proceed on this computer with the psi4 build.
""" % (sys.version[:6].strip()))
    sys.exit(1)

root_directory = os.path.dirname(os.path.realpath(__file__))
default_path = os.path.join(root_directory, 'build')

def parse_input():

    parser = ArgumentParser(description="Configure Psi4 using CMake",
                            formatter_class=argparse.AgumentDefaultsHelpFormatter)

    parser.add_argument('builddir', nargs='?',
            action='store',
            default=default_path,
            help='build directory [default: %(default)s]',
            metavar='build path')

    group = parser.add_argument_group('Basic options')
    # The C compiler
    group.add_argument('--with-cc',
            action='store',
            type=str,
            default=None,
            help='set the C compiler [default: pick automatically or based on CC=...]',
            metavar='STRING')
    # The C++ compiler
    group.add_argument('--with-cxx',
            action='store',
            type=str,
            default=None,
            help='set the C++ compiler [default: pick automatically or based on CXX=...]',
            metavar='STRING')
    # The Fortran compiler
    group.add_argument('--with-fc',
            action='store',
            type=str,
            default=None,
            help='set the Fortran compiler [default: pick automatically or based on FC=...]',
            metavar='STRING')
    # Libint maximum angular momentum.
    parser.add_argument('--with-max-am-eri',
                        metavar="= MAX_ANGULAR_MOMENTUM",
                        type=int,
                        default=5,
                        help='The maximum angular momentum level (1=p, 2=d, 3=f, etc.) for the libint and libderiv packages.  Note: A value of N implies a maximum first derivative of N-1, and maximum second derivative of N-2.')
    # Release, debug or profiling build
    group.add_argument('--type',
            nargs='?',
            action='store',
            type=str,
            choices=('release', 'debug', 'profile'),
            default='release',
            help='set the CMake build type [default: %(default)s]')
    # Install prefix
    group.add_argument('--prefix',
            action='store',
            type=str,
            default='/usr/local/psi4',
            help='set the install path for make install [default: %(default)s]',
            metavar='PATH')
    # Show CMake command
    group.add_argument('--show',
            action='store_true',
            default=False,
            help='show CMake command and exit [default: %(default)s]')
    group.add_argument('--with-cmake',
            action='store',
            type=str,
            default='cmake',
            help='set the CMake executable to use [default: cmake; e.g. --cmake cmake28]',
            metavar='STRING')
    
    group = parser.add_argument_group('Boost and Python options')
    group.add_argument('--with-boost-incdir',
            action='store',
            type=str
            default=None,
            help='The includes directory for boost.  If this is left blank cmake will attempt to find one on your system.  Failing that it will build one for you',
            metavar='PATH')
    group.add_argument('--with-boost-libdir',
            action='store',
            type=str
            default=None,
            help='The libraries directory for boost.  If this is left blank cmake will attempt to find one on your system.  Failing that it will build one for you',
            metavar='PATH')
    group.add_argument('--with-python',
            metavar='= PYTHON',
            action='store',
            type=str
            default=None,
            help='The Python interpreter (development version) to use.  CMake will detect one automatically, if omitted.')

    group = parser.add_argument_group('Parallelization')
    group.add_argument('--mpi',
            action='store_true',
            default=False,
            help='enable MPI [default: %(default)s]')
    group.add_argument('--sgi-mpt',
            action='store_true',
            default=False,
            help='enable SGI MPT [default: %(default)s]')
    group.add_argument('--omp',
            action='store_true',
            default=True,
            help='enable OpenMP [default: %(default)s]')

    group = parser.add_argument_group('Math libraries')
    group.add_argument('--mkl',
            nargs='?',
            action='store',
            choices=('sequential', 'parallel', 'cluster'),
            default='none',
            help='pass -mkl=STRING flag to the compiler and linker [default: None]')
    group.add_argument('--blas',
            action='store',
            default='auto',
            help='specify BLAS library; possible choices are "auto", "builtin", "none", or full path [default: %(default)s]',
            metavar='[{auto,builtin,none,/full/path/lib.a}]')
    group.add_argument('--lapack',
            action='store',
            default='auto',
            help='specify LAPACK library; possible choices are "auto", "builtin", "none", or full path [default: %(default)s]',
            metavar='[{auto,builtin,none,/full/path/lib.a}]')
    group.add_argument('--cray',
            action='store_true',
            default=False,
            help='use cray wrappers for BLAS/LAPACK and MPI which disables math detection and builtin math implementation [default: %(default)s]')
    group.add_argument('--csr',
            action='store_true',
            default=False,
            help='build using MKL compressed sparse row [default: %(default)s]')
    group.add_argument('--scalapack',
            action='store_true',
            default=False,
            help='build using SCALAPACK [default: %(default)s]')
    group.add_argument('--scalasca',
            action='store_true',
            default=False,
            help='build using SCALASCA profiler mode [default: %(default)s]')

    # Advanced options
    group = parser.add_argument_group('Advanced options')
    group.add_argument('--with-ldflags',
            action='store',
            default=None,
            help="Any extra flags to pass to the linker (usually -Llibdir -llibname type arguments). You shouldn't need this.",
            metavar='STRING')
    # Plugins
    group.add_argument('--with-plugins',
            action="store_true",
            default=False,
            help='Compile with support for plugins.')
    group.add_argument('--check',
            action='store_true',
            default=False,
            help='enable bounds checking [default: %(default)s]')
    group.add_argument('--coverage',
            action='store_true',
            default=False,
            help='enable code coverage [default: %(default)s]')
    group.add_argument('--static',
            action='store_true',
            default=False,
            help='link statically [default: %(default)s]')
    group.add_argument('--tests',
            action='store_true',
            default=False,
            help='build unit test suite [default: %(default)s]')
    group.add_argument('--vectorization',
            action='store_true',
            default=False,
            help='enable vectorization [default: %(default)s]')
    group.add_argument('-D',
            action="append",
            dest='define',
            default=[],
            help='forward directly to cmake (example: -D ENABLE_THIS=1 -D ENABLE_THAT=1); \
                    you can also forward CPP defintions all the way to the program \
                    (example: -D CPP="-DDEBUG")',
                    metavar='STRING')
    group.add_argument('--host',
            action='store',
            default=None,
            help="use predefined defaults for 'host'",
            metavar='STRING')
    group.add_argument('--generator',
            action='store',
            default=None,
            help='set the cmake generator [default: %(default)s]',
            metavar='STRING')
    group.add_argument('--timings',
            action='store_true',
            default=False,
            help='build using timings [default: %(default)s]')

    group = parser.add_argument_group('External libraries')
    # ERD package
    group.add_argument('--with-erd',
            action='store_true',
            default=False,
            help='Add support for the ERD integral package.')
    # GPU_DFCC package
    group.add_argument('--with-gpu-dfcc',
            action='store_true',
            default=False,
            help='Enable GPU_DFCC external project.')
    # Dummy plugin
    group.add_argument('--with-dummy-plugin',
            action='store_true',
            default=False,
            help='Enable dummy plugin external project.')

    group = parser.add_argument_group('Bypass compiler flags')
    group.add_argument('--with-fc-flags',
            action='store',
            type=str,
            default=None,
            help='Fortran flags [default: %(default)s]',
            metavar='STRING')
    group.add_argument('--with-cc-flags',
            action='store',
            type=str,
            default=None,
            help='C flags [default: %(default)s]',
            metavar='STRING')
    group.add_argument('--with-cxx-flags',
            action='store',
            type=str,
            default=None,
            help='C++ flags [default: %(default)s]',
            metavar='STRING')

    return parser.parse_args()


def check_cmake_exists(cmake_command):
    p = subprocess.Popen('%s --version' % cmake_command,
            shell=True,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE)
    if not ('cmake version' in p.communicate()[0]):
        print('   This code is built using CMake')
        print('')
        print('   CMake is not found')
        print('   get CMake at http://www.cmake.org/')
        print('   on many clusters CMake is installed')
        print('   but you have to load it first:')
        print('   $ module load cmake')
        sys.exit()

def translate_cmake(s):
    if s:
        return 'ON'
    else:
        return 'OFF'

def gen_cmake_command(args):
    # create cmake command from flags

    command = ''

    if args.fc:
        command += ' FC=%s'  % args.fc
    if args.cc:
        command += ' CC=%s'  % args.cc
    if args.cxx:
        command += ' CXX=%s' % args.cxx

    if sys.platform != "win32":
        command += ' %s' % args.cmake
    else:
        # fix for windows
        command = ' %s ' % args.cmake + command

    command += ' -DENABLE_MPI=%s'            % translate_cmake(args.mpi)
    command += ' -DENABLE_SGI_MPT=%s'        % translate_cmake(args.sgi_mpt)
    command += ' -DENABLE_OMP=%s'            % translate_cmake(args.omp)
    command += ' -DENABLE_VECTORIZATION=%s'  % translate_cmake(args.vectorization)
    command += ' -DENABLE_CSR=%s'            % translate_cmake(args.csr)
    command += ' -DENABLE_SCALAPACK=%s'      % translate_cmake(args.scalapack)
    command += ' -DENABLE_SCALASCA=%s'       % translate_cmake(args.scalasca)
    command += ' -DENABLE_TESTS=%s'          % translate_cmake(args.tests)
    command += ' -DENABLE_STATIC_LINKING=%s' % translate_cmake(args.static)

    if args.blas == 'builtin':
        command += ' -DENABLE_BUILTIN_BLAS=ON'
        command += ' -DENABLE_AUTO_BLAS=OFF'
    elif args.blas == 'auto':
        if (args.mkl != 'none') and not args.cray:
            command += ' -DENABLE_AUTO_BLAS=ON'
    elif args.blas == 'none':
        command += ' -DENABLE_AUTO_BLAS=OFF'
    else:
        if not os.path.isfile(args.blas):
            print('--blas=%s does not exist' % args.blas)
            sys.exit(1)
        command += ' -DEXPLICIT_BLAS_LIB=%s' % args.blas
        command += ' -DENABLE_AUTO_BLAS=OFF'

    if args.lapack == 'builtin':
        command += ' -DENABLE_BUILTIN_LAPACK=ON'
        command += ' -DENABLE_AUTO_LAPACK=OFF'
    elif args.lapack == 'auto':
        if (args.mkl != 'none') and not args.cray:
            command += ' -DENABLE_AUTO_LAPACK=ON'
    elif args.lapack == 'none':
        command += ' -DENABLE_AUTO_LAPACK=OFF'
    else:
        if not os.path.isfile(args.lapack):
            print('--lapack=%s does not exist' % args.lapack)
            sys.exit(1)
        command += ' -DEXPLICIT_LAPACK_LIB=%s' % args.lapack
        command += ' -DENABLE_AUTO_LAPACK=OFF'

    if args.cray:
        command += ' -DENABLE_CRAY_WRAPPERS=ON'
        command += ' -DENABLE_AUTO_BLAS=OFF'
        command += ' -DENABLE_AUTO_LAPACK=OFF'

    if args.mkl != 'none':
        if args.mkl == None:
            print('you have to choose between --mkl=[{sequential,parallel,cluster}]')
            sys.exit(1)
        command += ' -DMKL_FLAG="-mkl=%s"' % args.mkl
        command += ' -DENABLE_AUTO_BLAS=OFF'
        command += ' -DENABLE_AUTO_LAPACK=OFF'

    if args.explicit_libs:
        # remove leading and trailing whitespace
        # otherwise CMake complains
        command += ' -DEXPLICIT_LIBS="%s"' % args.explicit_libs.strip()
    
    if args.boost_headers:
        command += ' -DBOOST_INCLUDEDIR={0}'.format(args.with_boost_incdir)
    
    if args.boost_libs:
        command += ' -DBOOST_LIBRARYDIR={0}'.format(args.with_boost_libdir)
    
    if args.python:
        command += ' -DPYTHON_INTERPRETER={0}'.format(args.with_python)

    if args.extra_fc_flags:
        command += ' -DEXTRA_Fortran_FLAGS="%s"' % args.with_fc_flags
    if args.extra_cc_flags:
        command += ' -DEXTRA_C_FLAGS="%s"' % args.with_cc_flags
    if args.extra_cxx_flags:
        command += ' -DEXTRA_CXX_FLAGS="%s"' % args.with_cxx_flags

    if args.check:
        command += ' -DENABLE_BOUNDS_CHECK=ON'

    if args.coverage:
        command += ' -DENABLE_CODE_COVERAGE=ON'

    if args.prefix:
        command += ' -DCMAKE_INSTALL_PREFIX=' + args.prefix

    command += ' -DCMAKE_BUILD_TYPE=%s' % args.type

    if args.define:
        for definition in args.define:
            command += ' -D%s' % definition

    if args.generator:
        command += ' -G "%s"' % args.generator

    command += ' %s' % root_directory

    print('%s\n' % command)
    if args.show:
        sys.exit()
    return command

def print_build_help(build_path):
    print('   configure step is done')
    print('   now you need to compile the sources:')
    if (build_path == default_path):
        print('   $ cd build')
    else:
        print('   $ cd ' + build_path)
    print('   $ make')

def save_setup_command(argv, build_path):
    file_name = os.path.join(build_path, 'setup_command')
    f = open(file_name, 'w')
    f.write(" ".join(argv[:])+"\n")
    f.close()

def setup_build_path(build_path):
    if os.path.isdir(build_path):
        fname = os.path.join(build_path, 'CMakeCache.txt')
        if os.path.exists(fname):
            print('aborting setup - build directory %s which contains CMakeCache.txt exists already' % build_path)
            print('remove the build directory and then rerun setup')
            sys.exit(1)
    else:
        os.makedirs(build_path, 0755)

def run_cmake(command, build_path):
    topdir = os.getcwd()
    os.chdir(build_path)
    p = subprocess.Popen(command,
            shell=True,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE)
    s = p.communicate()[0]
    # print cmake output to screen
    print(s)
    # write cmake output to file
    f = open('setup_cmake_output', 'w')
    f.write(s)
    f.close()
    # change directory and return
    os.chdir(topdir)
    return s


def main(argv):
    args = parse_input()
    check_cmake_exists(args.cmake)
    build_path = args.builddir
    if not args.show:
        setup_build_path(build_path)
    if not configure_host(args):
        configure_default_compilers(args)
    command = gen_cmake_command(args)
    status = run_cmake(command, build_path)

    if 'Configuring incomplete' in status:
        # configuration was not successful
        if (build_path == default_path):
            # remove build_path iff not set by the user
            # otherwise removal can be dangerous
            shutil.rmtree(default_path)
    else:
        # configuration was successful
        save_setup_command(argv, build_path)
        print_build_help(build_path)

# host/system specific configurations
def configure_host(args):
    if args.host:
        host = args.host
    else:
        if sys.platform != "win32":
            u = os.uname()
        else:
            u = "Windows"
        host = string.join(u)
    msg = None
    # Generic systems
    if re.search('ubuntu', host, re.I):
        msg = "Configuring system: Ubuntu"
        configure_ubuntu(args)
    if re.search('fedora', host, re.I):
        msg = "Configuring system: Fedora"
        configure_fedora(args)
    if re.search('osx', host, re.I):
        msg = "Configuring system: MacOSX"
        configure_osx(args)
    if msg is None:
        return False
    if not args.show:
        print msg
    return True


def configure_default_compilers(args):

    if args.mpi and not args.fc and not args.cc and not args.cxx:
        # only --mpi flag but no --fc, --cc, --cxx
        # set --fc, --cc, --cxx to mpif90, mpicc, mpicxx
        args.fc  = 'mpif90'
        args.cc  = 'mpicc'
        args.cxx = 'mpicxx'

    if not args.mpi:
        # if compiler starts with 'mp' turn on mpi
        # it is possible to call compilers with long paths
        if  args.cc  and os.path.basename(args.cc).lower().startswith('mp')  or \
            args.cxx and os.path.basename(args.cxx).lower().startswith('mp') or \
            args.fc  and os.path.basename(args.fc).lower().startswith('mp'):
            args.mpi = 'on'
        # if compiler starts with 'openmpi' turn on mpi
        # it is possible to call compilers with long paths
        if  args.cc  and os.path.basename(args.cc).lower().startswith('openmpi')  or \
            args.cxx and os.path.basename(args.cxx).lower().startswith('openmpi') or \
            args.fc  and os.path.basename(args.fc).lower().startswith('openmpi'):
            args.mpi = 'on'

    if not args.fc:
        args.fc = 'gfortran'
    if not args.cc:
        args.cc = 'gcc'
    if not args.cxx:
        args.cxx = 'g++'


configure_ubuntu = configure_default_compilers
configure_fedora = configure_default_compilers
configure_osx    = configure_default_compilers


if __name__ == '__main__':
    main(sys.argv)
