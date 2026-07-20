#!/bin/bash

BASEDIR="$(dirname "$0")"
HSJSON="https://api.hearthstonejson.com/v1"

for lang in deDE enUS esES esMX frFR itIT jaJP koKR plPL ptBR ruRU thTH zhCN zhTW; do
	echo "Downloading cards.$lang.json"
	curl --fail --location --retry 3 \
		--output "$BASEDIR/../HSTracker/Resources/Cards/cardsDB.$lang.json" \
		"$HSJSON/latest/$lang/cards.json"
done
