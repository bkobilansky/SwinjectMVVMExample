//
//  ImageSearchSpec.swift
//  SwinjectMVVMExample
//
//  Created by Yoichi Tagaya on 8/22/15.
//  Copyright © 2015 Swinject Contributors. All rights reserved.
//

import Quick
import Nimble
import ReactiveCocoa
@testable import ExampleModel

class ImageSearchSpec: QuickSpec {
    // MARK: Stub
    class GoodStubNetwork: Networking {
        func requestJSON(url: String, parameters: [String : AnyObject]?) -> SignalProducer<AnyObject, NetworkError> {
            var imageJSON0 = imageJSON
            imageJSON0["id"] = 0
            var imageJSON1 = imageJSON
            imageJSON1["id"] = 1
            let json: [String: AnyObject] = [
                "totalHits": 123,
                "hits": [imageJSON0, imageJSON1]
            ]
            
            return SignalProducer { observer, disposable in
                observer.sendNext(json)
                observer.sendCompleted()
            }
            .observeOn(QueueScheduler())
        }
        
        func requestImage(url: String) -> SignalProducer<UIImage, NetworkError> {
            return SignalProducer.empty
        }
    }
    
    class BadStubNetwork: Networking {
        func requestJSON(url: String, parameters: [String : AnyObject]?) -> SignalProducer<AnyObject, NetworkError> {
            let json = [String: AnyObject]()
            
            return SignalProducer { observer, disposable in
                observer.sendNext(json)
                observer.sendCompleted()
            }
            .observeOn(QueueScheduler())
        }
        
        func requestImage(url: String) -> SignalProducer<UIImage, NetworkError> {
            return SignalProducer.empty
        }
    }

    class ErrorStubNetwork: Networking {
        func requestJSON(url: String, parameters: [String : AnyObject]?) -> SignalProducer<AnyObject, NetworkError> {
            return SignalProducer { observer, disposable in
                observer.sendFailed(.NotConnectedToInternet)
            }
            .observeOn(QueueScheduler())
        }
        
        func requestImage(url: String) -> SignalProducer<UIImage, NetworkError> {
            return SignalProducer.empty
        }
    }
    
    class CountConfigurableStubNetwork: Networking {
        var imageCountToEmit = 100
        
        func requestJSON(url: String, parameters: [String : AnyObject]?) -> SignalProducer<AnyObject, NetworkError> {
            func createImageJSON(id id: Int) -> [String: AnyObject] {
                var json = imageJSON
                json["id"] = id
                return json
            }
            let json: [String: AnyObject] = [
                "totalHits": 150,
                "hits": (0..<imageCountToEmit).map { createImageJSON(id: $0) }
            ]
            
            return SignalProducer { observer, disposable in
                observer.sendNext(json)
                observer.sendCompleted()
            }.observeOn(QueueScheduler())
        }
        
        func requestImage(url: String) -> SignalProducer<UIImage, NetworkError> {
            return SignalProducer.empty
        }
    }
    
    // MARK: - Mock
    class MockNetwork: Networking {
        var passedParameters: [String : AnyObject]?

        func requestJSON(url: String, parameters: [String : AnyObject]?) -> SignalProducer<AnyObject, NetworkError> {
            passedParameters = parameters
            return SignalProducer.empty
        }
        
        func requestImage(url: String) -> SignalProducer<UIImage, NetworkError> {
            return SignalProducer.empty
        }
    }


    // MARK: - Spec
    override func spec() {
        describe("Response") {
            it("returns images if the network works correctly.") {
                var response: ResponseEntity? = nil
                let search = ImageSearch(network: GoodStubNetwork())
                search.searchImages(nextPageTrigger: SignalProducer.empty)
                    .on(next: { response = $0 })
                    .start()
                
                expect(response).toEventuallyNot(beNil())
                expect(response?.totalCount).toEventually(equal(123))
                expect(response?.images.count).toEventually(equal(2))
                expect(response?.images[0].id).toEventually(equal(0))
                expect(response?.images[1].id).toEventually(equal(1))
            }
            it("sends an error if the network returns incorrect data.") {
                var error: NetworkError? = nil
                let search = ImageSearch(network: BadStubNetwork())
                search.searchImages(nextPageTrigger: SignalProducer.empty)
                    .on(failed: { error = $0 })
                    .start()
                
                expect(error).toEventually(equal(NetworkError.IncorrectDataReturned))
            }
            it("passes the error sent by the network.") {
                var error: NetworkError? = nil
                let search = ImageSearch(network: ErrorStubNetwork())
                search.searchImages(nextPageTrigger: SignalProducer.empty)
                    .on(failed: { error = $0 })
                    .start()
                
                expect(error).toEventually(equal(NetworkError.NotConnectedToInternet))
            }
        }
        describe("Pagination") {
            describe("page parameter") {
                var mockNetwork: MockNetwork!
                var search: ImageSearch!
                beforeEach {
                    mockNetwork = MockNetwork()
                    search = ImageSearch(network: mockNetwork)
                }
                
                it("sets page to 1 at the beginning.") {
                    search.searchImages(nextPageTrigger: SignalProducer.empty).start()
                    expect(mockNetwork.passedParameters?["page"] as? Int).toEventually(equal(1))
                }
                it("increments page by nextPageTrigger") {
                    let trigger = SignalProducer<(), NoError>(value: ()) // Trigger once.
                    search.searchImages(nextPageTrigger: trigger).start()
                    expect(mockNetwork.passedParameters?["page"] as? Int).toEventually(equal(2))
                }
            }
            describe("completed event") {
                var network: CountConfigurableStubNetwork!
                var search: ImageSearch!
                var nextPageTrigger: (SignalProducer<(), NoError>, Observer<(), NoError>)! // SignalProducer buffer
                beforeEach {
                    network = CountConfigurableStubNetwork()
                    search = ImageSearch(network: network)
                    nextPageTrigger = SignalProducer.buffer()
                }
                
                it("sends completed when newly found images are less than the max number of images per page.") {
                    var completedCalled = false
                    network.imageCountToEmit = Pixabay.maxImagesPerPage
                    search.searchImages(nextPageTrigger: nextPageTrigger.0)
                        .on(completed: { completedCalled = true })
                        .start()
                    
                    nextPageTrigger.1.sendNext(()) // Emits `maxImagesPerPage` (50) images, which mean more images possibly exit.
                    network.imageCountToEmit = Pixabay.maxImagesPerPage - 1
                    nextPageTrigger.1.sendNext(()) // Emits only 49, which mean no more images exist.
                    expect(completedCalled).toEventually(beTrue(), timeout: 2)
                }
                it("sends completed when total loaded images are equal to the total number of images specified by the response.") {
                    var completedCalled = false
                    network.imageCountToEmit = Pixabay.maxImagesPerPage
                    search.searchImages(nextPageTrigger: nextPageTrigger.0)
                        .on(completed: { completedCalled = true })
                        .start() // Will emit `maxImagesPerPage` (50) images.
                    
                    nextPageTrigger.1.sendNext(()) // Will emit `maxImagesPerPage` (50) images.
                    nextPageTrigger.1.sendNext(()) // Will emit `maxImagesPerPage` (50) images, and reach the toal number (150).
                    expect(completedCalled).toEventually(beTrue())
                }
                it("does not send completed otherwise.") {
                    var completedCalled = false
                    network.imageCountToEmit = Pixabay.maxImagesPerPage
                    search.searchImages(nextPageTrigger: nextPageTrigger.0)
                        .on(completed: { completedCalled = true })
                        .start() // Will emit `maxImagesPerPage` (50) images.
                    
                    nextPageTrigger.1.sendNext(()) // Will emit `maxImagesPerPage` (50) images, and still not reach the total number (150).
                    expect(completedCalled).toEventuallyNot(beTrue())
                }
            }
        }
    }
}
