.PHONY: build run clean deploy

build:
	hugo --destination docs
	cp static/CNAME docs

run:
	hugo server

clean:
	rm -rf public
	rm -rf docs

deploy: build
	git add -A
	git commit --author "Nimor111 <georgi.bojinov@hotmail.com>" -m "Deploy..."
	git push origin master
