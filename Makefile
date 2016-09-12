
run:
	docker-compose run --rm -p 8080:80 dev_pece

stop:
	docker-compose stop

build:
	docker-compose run --rm dev_pece echo "$pwd"

push:
	docker-compose run --rm dev_pece echo "Pushado! :)"
