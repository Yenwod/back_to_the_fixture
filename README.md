back_to_the_fixture
========
Based on [ar_fixtures](https://github.com/topfunky/ar_fixtures) by Geoffrey Grosenbach.

back_to_the_fixture let's you export your ActiveRecord models to reloadable fixtures for tests or database population. 
It's been updated for rails 3 and has some new and some improved functionality.

But aren't fixtures dead?
-----
Most people preffer to use factories over fixtures for testing purposes because working with and maintaing fixtures,
especially for tests, can be unwieldy. However, fixtures can still be useful in other scenarios:

  * Static models, like a `MembershipPlan`, where it's a few records that should be the same in all enviroments. 
  * Testing complex modeling, where there is a network of record relationships and conditions
  * Exporting records from production for use in development
  * Snapshot & backup of records 
  * Simple Export / Import

Getting Started 
-------
Put this in your gemfile
```
gem 'back_to_the_fixture'
```


