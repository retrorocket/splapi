# splapi

[スプラトゥーンのステージ情報がとれるやつ（非公式）](http://splapi.retrorocket.biz/)  
[splapi - スプラトゥーンのステージ情報がとれるやつ · Apiary](http://docs.splapi.apiary.io/#)

## スクリプト内容
* Scraper
 - イカリングの内容をスクレーピングして、MongoDBに格納する。
 - 主な使用モジュール：WWWW::Mechanize, Web::Scraper

* API
 - 受け付けたクエリからDB内を検索し、結果をJSONとしてクライアントに返却する。
 - 主な使用モジュール：Mojolicious::Lite
