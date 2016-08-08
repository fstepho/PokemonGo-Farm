FROM php:5.6-apache


RUN rm /bin/sh && ln -s /bin/bash /bin/sh

RUN apt-get update
RUN apt-get install -y git-core
RUN apt-get install -y curl 
RUN apt-get install -y wget

# RUN apt-get install -y python-dev build-essential 
# RUN apt-get install -y python-pip
# RUN apt-get install -y python-virtualenv

RUN apt-get install -y unzip

RUN whereis gcc make
RUN gcc -v
RUN make -v

# RUN pip install --upgrade pip

RUN curl -sL https://deb.nodesource.com/setup_4.x 
RUN apt-get install -y nodejs
RUN apt-get install -y npm
RUN ln -s /usr/bin/nodejs /usr/bin/node



# divert many traces of Debian Python (so that they are not used by mistake)
# https://bugs.debian.org/33263 :(
RUN set -ex \
	&& for bits in \
#		/etc/python* \
		/usr/bin/*2to3* \
		/usr/bin/*python* \
		/usr/bin/pdb* \
		/usr/bin/py* \
#		/usr/lib/python* \
#		/usr/share/python \
	; do \
		dpkg-divert --rename "$bits"; \
	done

# http://bugs.python.org/issue19846
# > At the moment, setting "LANG=C" on a Linux system *fundamentally breaks Python 3*, and that's not OK.
ENV LANG C.UTF-8

# gpg: key 18ADD4FF: public key "Benjamin Peterson <benjamin@python.org>" imported
ENV GPG_KEY C01E1CAD5EA2C4F0B8E3571504C367C218ADD4FF

ENV PYTHON_VERSION 2.7.12

# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION 8.1.2

RUN set -ex \
	&& buildDeps=' \
		tcl-dev \
		tk-dev \
	' \
	&& runDeps=' \
		tcl \
		tk \
	' \
	&& apt-get update && apt-get install -y $runDeps $buildDeps --no-install-recommends && rm -rf /var/lib/apt/lists/* \
	&& curl -fSL "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz" -o python.tar.xz \
	&& curl -fSL "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc" -o python.tar.xz.asc \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$GPG_KEY" \
	&& gpg --batch --verify python.tar.xz.asc python.tar.xz \
	&& rm -r "$GNUPGHOME" python.tar.xz.asc \
	&& mkdir -p /usr/src/python \
	&& tar -xJC /usr/src/python --strip-components=1 -f python.tar.xz \
	&& rm python.tar.xz \
	\
	&& cd /usr/src/python \
	&& ./configure \
		--enable-shared \
		--enable-unicode=ucs4 \
	&& make -j$(nproc) \
	&& make install \
	&& ldconfig \
	&& curl -fSL 'https://bootstrap.pypa.io/get-pip.py' | python2 \
	&& pip install --no-cache-dir --upgrade pip==$PYTHON_PIP_VERSION \
	&& [ "$(pip list | awk -F '[ ()]+' '$1 == "pip" { print $2; exit }')" = "$PYTHON_PIP_VERSION" ] \
	&& find /usr/local -depth \
		\( \
		    \( -type d -a -name test -o -name tests \) \
		    -o \
		    \( -type f -a -name '*.pyc' -o -name '*.pyo' \) \
		\) -exec rm -rf '{}' + \
	&& apt-get purge -y --auto-remove $buildDeps \
	&& rm -rf /usr/src/python ~/.cache

# install "virtualenv", since the vast majority of users of this image will want it
RUN pip install --no-cache-dir virtualenv






ARG timezone=Etc/UTC
RUN echo $timezone > /etc/timezone \
    && ln -sfn /usr/share/zoneinfo/$timezone /etc/localtime \
    && dpkg-reconfigure -f noninteractive tzdata

RUN apt-get update \
    && apt-get install -y python-protobuf
RUN cd /tmp
RUN wget "http://pgoapi.com/pgoencrypt.tar.gz" 
RUN mkdir /usr/src/app
RUN tar zxvf pgoencrypt.tar.gz && cd pgoencrypt/src && make && cp libencrypt.so /usr/src/app/encrypt.so

ENV LD_LIBRARY_PATH /usr/src/app

COPY config/php.ini-development /usr/local/etc/php/php.ini
COPY config/apache-farm.conf /etc/apache2/sites-available/
RUN a2dissite 000-default.conf
RUN a2ensite apache-farm.conf
RUN a2enmod rewrite

COPY . /var/www/html/
RUN cd /var/www/html
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
RUN php -r "if (hash_file('SHA384', 'composer-setup.php') === 'e115a8dc7871f15d853148a7fbac7da27d6c0030b848d9b3dc09e2a0388afed865e6a3d6b3c0fad45c48e2b5fc1196ae') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
RUN php composer-setup.php
RUN php -r "unlink('composer-setup.php');"
RUN php composer.phar install
RUN npm install -g bower
RUN bower install --allow-root --force
RUN cp app/config/parameters.json.dist app/config/parameters.json
RUN cp PokemonGo-Bot/release_config.json.example PokemonGo-Bot/release_config.json
RUN cd /var/www/html/PokemonGo-Bot && pip install -r requirements.txt && virtualenv . && source bin/activate

RUN chown -R www-data:www-data /var/www/html