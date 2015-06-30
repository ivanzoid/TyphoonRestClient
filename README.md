# TyphoonRestClient

TyphoonRestClient is flexible HTTP client for integration against contract-first web service.
It provides facilities for customisable serialisation / marshalling, validation and stubbing requests.

TRC helps to quickly achieve end-to-end proof of concept, at the same time as providing a robust platform for deploying into demanding production environments.

# Features

* Response and request body validation, using schema file.
* Automatically transforms basic types such a date into model object (NSDate)
* Automatic marshalling of model objects
* Common solution for server errors handling
* User able to apply common rules to any NSURLRequest created by TRC.
* User has control over sending of each NSURLRequest.
* Easy to stub any network call
* Has extendable architecture
