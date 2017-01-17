## スクリプト内容
* Scraper
 - イカリングの出力するjsonからの内容をMongoDBに格納する。
 - 主な使用モジュール：WWWW::Mechanize, JSON

* API
 - 受け付けたクエリからDB内を検索し、結果をJSONとしてクライアントに返却する。
 - 主な使用モジュール：Mojolicious::Lite
