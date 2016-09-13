.PHONY: run stop clean distro

run:
	docker-compose run --rm -p 8080:80 dev_pece

stop:
	docker-compose stop

clean:
	docker-compose down

distro:
	docker-compose run --rm production gulp pack-distro
