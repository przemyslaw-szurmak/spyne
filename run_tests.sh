#!/bin/bash -x
#
# Sets up a Python testing environment from scratch. Mainly written for Jenkins.
#
# Requirements:
#   A working build environment inside the container with OpenSSL, bzip2,
#   libxml2 and libxslt development files. Only tested on Linux variants.
#
#   Last time we looked, for ubuntu, that meant:
#     $ sudo apt-get install build-essential libssl-dev lilbbz2-dev \
#                                                       libxml2-dev libxslt-dev
#
# Usage:
#   Example:
#
#     $ PYFLAV=cpy-3.3 ./run_tests.sh
#
#   Variables:
#     - PYFLAV: Defaults to 'cpy-2.7'. See other values below.
#     - WORKSPACE: Defaults to $PWD. It's normally set by Jenkins.
#     - MAKEOPTS: Defaults to '-j2'.
#     - MONOVER: Defaults to '2.11.4'. Only relevant for ipy-* flavors.
#
# Jenkins guide:
#   1. Create a 'Multi configuration project'.
#   2. Set up stuff like git repo the usual way.
#   3. In the 'Configuration Matrix' section, create a user-defined axis named
#      'PYVER'. and set it to the Python versions you'd like to test, separated
#      by whitespace. For example: 'cpy-2.7 cpy-3.4'
#   4. Add a new "Execute Shell" build step and type in './run_tests.sh'.
#   5. Add a new "Publish JUnit test report" post-build action and type in
#      'test_result.*.xml'
#   6. Add a new "Publish Cobertura Coverage Report" post-build action and type
#      in 'coverage.xml'. Install the "Cobertura Coverage Report" plug-in if you
#      don't see this option.
#   7. Nonprofit!
#


# Sanitization
[ -z "$PYFLAV" ] && PYFLAV=cpy-2.7;
[ -z "$MONOVER" ] && MONOVER=2.11.4;
[ -z "$WORKSPACE" ] && WORKSPACE="$PWD";
[ -z "$MAKEOPTS" ] && MAKEOPTS="-j2";

PYIMPL=(${PYFLAV//-/ });
PYVER=${PYIMPL[1]};
PYFLAV="${PYFLAV/-/}";
PYFLAV="${PYFLAV/./}";
if [ -z "$PYVER" ]; then
    PYVER=${PYIMPL[0]};
    PYIMPL=cpy;
    PYFLAV=cpy${PYVER/./};
else
    PYIMPL=${PYIMPL[0]};
fi

PYNAME=python$PYVER;

if [ -z "$FN" ]; then
    declare -A URLS;
    URLS["cpy27"]="2.7.10/Python-2.7.10.tar.xz";
    URLS["cpy34"]="3.4.3/Python-3.4.3.tar.xz";
    URLS["cpy35"]="3.5.0/Python-3.5.0.tar.xz";
    URLS["jyt27"]="2.7-b2/jython-installer-2.7-b2.jar";
    URLS["ipy27"]="ipy-2.7.4.zip";

    FN="${URLS["$PYFLAV"]}";

    if [ -z "$FN" ]; then
        echo "Unknown Python version $PYFLAV";
        exit 2;
    fi;
fi;

# tox compat
declare -A TOX_ENVS;
TOX_ENVS["cpy26"]="py26,py26-dj1.6.x";
TOX_ENVS["cpy27"]="py27,py27-dj1.6.x,py27-dj1.7.x,py27-dj1.8.x";
TOX_ENVS["cpy33"]="py33,py33-dj1.7.x,py33-dj1.8.x";
TOX_ENVS["cpy34"]="py34,py34-dj1.7.x,py34-dj1.8.x";
TOX_ENVS["cpy35"]="py35,py35-dj1.7.x,py35-dj1.8.x";

# Initialization
IRONPYTHON_URL_BASE=https://github.com/IronLanguages/main/archive;
CPYTHON_URL_BASE=http://www.python.org/ftp/python;
JYTHON_URL_BASE=http://search.maven.org/remotecontent?filepath=org/python/jython-installer;
MAKE="make $MAKEOPTS";


# Set specific variables
if [ $PYIMPL == "cpy" ]; then
    PREFIX="$(basename $(basename $FN .tgz) .tar.xz)";

elif [ $PYIMPL == "ipy" ]; then
    PREFIX="$(basename $FN .zip)";
    MONOPREFIX="$WORKSPACE/mono-$MONOVER"
    XBUILD="$MONOPREFIX/bin/xbuild"

elif [ $PYIMPL == "jyt" ]; then
    PYNAME=jython;
    PREFIX="$(basename $FN .jar)";
fi;

# Set common variables
PYTHON="$WORKSPACE/$PREFIX/bin/$PYNAME";
PIP="$WORKSPACE/$PREFIX/bin/pip$PYVER";
TOX="$WORKSPACE/$PREFIX/bin/tox";
TOX2="$HOME/.local/bin/tox"


# Set up requested python environment.
if [ $PYIMPL == 'cpy' ]; then
    if [ ! -x "$PYTHON" ]; then
      (
        mkdir -p .data; cd .data;

        wget -ct0 $CPYTHON_URL_BASE/$FN;
        tar xf $(basename $FN);
        cd "$PREFIX";
        ./configure --prefix="$WORKSPACE/$PREFIX" --with-pydebug --with-ensurepip;
        $MAKE && make install;
      );
    fi;

elif [ $PYIMPL == 'jyt' ]; then
    if [ ! -x "$PYTHON" ]; then
      (
        mkdir -p .data; cd .data;

        FILE=$(basename $FN);
        wget -O $FILE -ct0 "$JYTHON_URL_BASE/$FN";
        java -jar $FILE -s -d "$WORKSPACE/$PREFIX"

      );
    fi

elif [ $PYIMPL == 'ipy' ]; then
    # Set up Mono first
    # See: http://www.mono-project.com/Compiling_Mono_From_Tarball
    if [ ! -x "$XBUILD" ]; then
      (
        mkdir -p .data; cd .data;

        wget -ct0 http://download.mono-project.com/sources/mono/mono-$MONOVER.tar.bz2
        tar xf mono-$MONOVER.tar.bz2;
        cd mono-$MONOVER;
        ./configure --prefix=$WORKSPACE/mono-$MONOVER;
        $MAKE && make install;
      );
    fi

    # Set up IronPython
    # See: https://github.com/IronLanguages/main/wiki/Building#the-mono-runtime
    if [ ! -x "$PYTHON" ]; then
      (
        mkdir -p .data; cd .data;
        export PATH="$(dirname "$XBUILD"):$PATH"

        wget -ct0 "$IRONPYTHON_URL_BASE/$FN";
        unzip -q "$FN";
        cd "main-$PREFIX";

        $XBUILD /p:Configuration=Release Solutions/IronPython.sln || exit 1

        mkdir -p "$(dirname "$PYTHON")";
        echo 'mono "$PWD/bin/Release/ir.exe" "${@}"' > $PYTHON;
        chmod +x $PYTHON;
      ) || exit 1;
    fi;

fi;


# Set up pip
$PYTHON -m ensurepip --upgrade

# Set up tox
if [ ! -x "$TOX" ]; then
   $PIP install tox;
fi;


set


if [ "$JENKINS_UR" == "https://spyne.ci.cloudbees.com/" ]; then

    export POSTGRESQL_VERSION=9.4.5
    curl -s -o use-postgresql https://repository-cloudbees.forge.cloudbees.com/distributions/ci-addons/postgresql/use-postgresql
    source ./use-postgresql

fi


if [ $PYIMPL == 'cpy' ]; then
    # Run tests. Tox runs coverage.
    TENV=${TOX_ENVS[$PYFLAV]};
    PATH="$WORKSPACE/$PREFIX/bin":"$PATH" BASEPYTHON="$PYTHON" "$TOX" --version
    PATH="$WORKSPACE/$PREFIX/bin":"$PATH" BASEPYTHON="$PYTHON" "$TOX" -e "$TENV" || true;

else
    # Run tests. No coverage in jython.
    $PYTHON setup.py test || true;

fi;
