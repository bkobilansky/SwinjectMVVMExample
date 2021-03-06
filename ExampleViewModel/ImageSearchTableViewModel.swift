//
//  ImageSearchTableViewModel.swift
//  SwinjectMVVMExample
//
//  Created by Yoichi Tagaya on 8/22/15.
//  Copyright © 2015 Swinject Contributors. All rights reserved.
//

import ReactiveCocoa
import ExampleModel

public final class ImageSearchTableViewModel: ImageSearchTableViewModeling {
    public var cellModels: AnyProperty<[ImageSearchTableViewCellModeling]> { return AnyProperty(_cellModels) }
    public var searching: AnyProperty<Bool> { return AnyProperty(_searching) }
    public var errorMessage: AnyProperty<String?> { return AnyProperty(_errorMessage) }
    
    private let _cellModels = MutableProperty<[ImageSearchTableViewCellModeling]>([])
    private let _searching = MutableProperty<Bool>(false)
    private let _errorMessage = MutableProperty<String?>(nil)
    
    /// Accepts property injection.
    public var imageDetailViewModel: ImageDetailViewModelModifiable?
    
    public var loadNextPage: Action<(), (), NoError> {
        return Action(enabledIf: nextPageLoadable) { _ in
            return SignalProducer { observer, disposable in
                if let (_, observer) = self.nextPageTrigger.value {
                    self._searching.value = true
                    observer.sendNext(())
                }
            }
        }
    }
    private var nextPageLoadable: AnyProperty<Bool> {
        return AnyProperty(
            initialValue: false,
            producer: searching.producer.combineLatestWith(nextPageTrigger.producer).map { searching, trigger in
                !searching && trigger != nil
            })
    }
    private let nextPageTrigger = MutableProperty<(SignalProducer<(), NoError>, Observer<(), NoError>)?>(nil) // SignalProducer buffer

    private let imageSearch: ImageSearching
    private let network: Networking
    
    private var foundImages = [ImageEntity]()
    
    public init(imageSearch: ImageSearching, network: Networking) {
        self.imageSearch = imageSearch
        self.network = network
    }
    
    public func startSearch() {
        func toCellModel(image: ImageEntity) -> ImageSearchTableViewCellModeling {
            return ImageSearchTableViewCellModel(image: image, network: self.network) as ImageSearchTableViewCellModeling
        }
        
        _searching.value = true
        nextPageTrigger.value = SignalProducer<(), NoError>.buffer()
        let (trigger, _) = nextPageTrigger.value!

        imageSearch.searchImages(nextPageTrigger: trigger)
            .map { response in
                (response.images, response.images.map { toCellModel($0) })
            }
            .observeOn(UIScheduler())
            .on(next: { images, cellModels in
                self.foundImages += images
                self._cellModels.value += cellModels
                self._searching.value = false
            })
            .on(failed: { error in
                self._errorMessage.value = error.description
            })
            .on(event: { event in
                switch event {
                case .Completed, .Failed, .Interrupted:
                    self.nextPageTrigger.value = nil
                    self._searching.value = false
                default:
                    break
                }
            })
            .start()
    }

    public func selectCellAtIndex(index: Int) {
        imageDetailViewModel?.update(foundImages, atIndex: index)
    }
}
