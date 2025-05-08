//
//  ViewController.swift
//  newcard
//
//

import UIKit
import SceneKit
import ARKit
import Vision
import AVFoundation


extension String {
    func widthOfString(usingFont font: UIFont) -> CGFloat {
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = self.size(withAttributes: fontAttributes)
        return size.width
    }
}


class ViewController: UIViewController, ARSCNViewDelegate {
    
    @IBOutlet var sceneView: ARSCNView!
    private var currentNodes: [SCNNode] = []
    private var audioPlayer: AVAudioPlayer?
    var recognitionStartTime: Date?
    var hasRecordedInitialRecognition = false
    
    private var playButton: UIButton!
    private var meaningLabel: UILabel!
    
    /*private let wordAssets: [String: (modelName: String, audioName: String, meaning: String, hasAnimation: Bool)] = [
        "hang": ("hourglass.usdz", "hourglass.mp3", "意味: 砂時計", false),
        "professional": ("astrolabe.usdz", "astrolabe.mp3", "意味: 天体観測儀", false),
        "trade": ("gramophone.usdz", "gramophone.mp3", "意味: 蓄音機", false),
        "direction": ("catapult.usdz", "catapult.mp3", "意味: カタパルト", false),
        "choice": ("chandelier.usdz", "chandelier.mp3", "意味: シャンデリア", false),
        "experience": ("obelisk.usdz", "obelisk.mp3", "意味: オベリスク", false),
        "difficult": ("tesseract.usdz", "tesseract.mp3", "意味: テッセラクト", false),
        "explode": ("explode.usdz", "explode.mp3", "意味: 爆発", true), // Assuming this one has an animation
        "dinosaur": ("dinosaur.usdz", "dinosaur.mp3", "意味: 恐竜", true)  // Assuming this one has an animation
    ]*/
    
    private var wordAssets: [String: (modelName: String, audioName: String, meaning: String, hasAnimation: Bool)] = [:]


    private var lastDetectedWord: String? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.showsStatistics = true
        sceneView.scene = SCNScene()
        
        setupUI()
        startTextDetection()
        loadWordAssets()
        
        let screenSize = UIScreen.main.bounds
        let screenWidth = screenSize.width
        let screenHeight = screenSize.height
        
    }
    
    func loadWordAssets() {
            if let url = Bundle.main.url(forResource: "wordAssets", withExtension: "json") {
                do {
                    let data = try Data(contentsOf: url)
                    let json = try JSONSerialization.jsonObject(with: data, options: [])
                    if let array = json as? [[String: Any]] {
                        for item in array {
                            if let word = item["word"] as? String,
                               let modelName = item["modelName"] as? String,
                               let audioName = item["audioName"] as? String,
                               let meaning = item["meaning"] as? String,
                               let hasAnimation = item["hasAnimation"] as? Bool {
                                wordAssets[word] = (modelName: modelName, audioName: audioName, meaning: meaning, hasAnimation: hasAnimation)
                            }
                        }
                    }
                } catch {
                    print("Error loading word assets: \(error)")
                }
            }
        }

    func setupUI() {
        playButton = UIButton(type: .system)
        playButton.setTitle("▶️ Play", for: .normal)
        playButton.addTarget(self, action: #selector(playAudio), for: .touchUpInside)
        playButton.frame = CGRect(x: 20, y: view.frame.height - 100, width: 80, height: 40)
        playButton.isHidden = true
        view.addSubview(playButton)
        
        meaningLabel = UILabel()
        meaningLabel.font = UIFont.systemFont(ofSize: 16)
        meaningLabel.textAlignment = .right
        meaningLabel.frame = CGRect(x: view.frame.width - 150, y: view.frame.height - 100, width: 130, height: 40)
        meaningLabel.isHidden = true
        view.addSubview(meaningLabel)
        
        let pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        sceneView.addGestureRecognizer(pinchGestureRecognizer)
        
       

        let swipeLeftGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeGesture(_:)))
        swipeLeftGestureRecognizer.direction = .left
        sceneView.addGestureRecognizer(swipeLeftGestureRecognizer)

        let swipeRightGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeGesture(_:)))
        swipeRightGestureRecognizer.direction = .right
        sceneView.addGestureRecognizer(swipeRightGestureRecognizer)


        
    }
    
    @objc func playAudio() {
        if let word = lastDetectedWord, let asset = wordAssets[word] {
            guard let url = Bundle.main.url(forResource: asset.audioName, withExtension: nil) else {
                print("Audio file not found!")
                return
            }
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.play()
            } catch {
                print("Failed to play audio: \(error)")
            }
        }
    }

    @objc func handlePinchGesture(_ recognizer: UIPinchGestureRecognizer) {
        guard let node = currentNodes.last else { return }
        
        if recognizer.state == .changed {
            let scale = Float(recognizer.scale)
            let currentScale = node.scale
            let newScale = SCNVector3(x: currentScale.x * scale, y: currentScale.y * scale, z: currentScale.z * scale)
            node.scale = newScale
            recognizer.scale = 1.0
        }
    }

    @objc func handleSwipeGesture(_ recognizer: UISwipeGestureRecognizer) {
        guard let node = currentNodes.last else { return }

        if recognizer.direction == .left {
            node.eulerAngles.y -= 0.1
        } else if recognizer.direction == .right {
            node.eulerAngles.y += 0.1
        }
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    func startTextDetection() {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            self.recognitionStartTime = Date()
            
            if let observations = request.results as? [VNRecognizedTextObservation] {
                self.updateUIBasedOnText(observations: observations)
            }
        }
        request.recognitionLevel = .accurate

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard let currentFrame = self.sceneView.session.currentFrame else { return }
            let image = currentFrame.capturedImage
            let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .right, options: [:])
            try? handler.perform([request])
        }
    }


    // Helper function to convert CGRect from UIKit coordinates to Vision coordinates
    func scaleRectToImage(rect: CGRect) -> CGRect {
        let imageSize = sceneView.bounds.size
        let scaleX = 1.0 / imageSize.width
        let scaleY = 1.0 / imageSize.height
        let x = rect.origin.x * scaleX
        let y = (imageSize.height - rect.origin.y - rect.size.height) * scaleY
        let width = rect.size.width * scaleX
        let height = rect.size.height * scaleY
        return CGRect(x: x, y: y, width: width, height: height)
    }

    

    func updateUIBasedOnText(observations: [VNRecognizedTextObservation]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let startTime = self.recognitionStartTime {
                        let responseTime = Date().timeIntervalSince(startTime)
                        print("Response time: \(responseTime) seconds")
                        self.hasRecordedInitialRecognition = true
                    }

            var maxWordBoxes: [String: (box: CGRect, meaning: String)] = [:]

            for observation in observations {
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                let word = topCandidate.string.lowercased()
                let wordPattern = "^[a-zA-Z]+$"
                if let _ = word.range(of: wordPattern, options: .regularExpression), word.count < 15 {
                    let currentBoxArea = observation.boundingBox.width * observation.boundingBox.height

                    for (assetWord, assetDetails) in self.wordAssets {
                        if word.contains(assetWord) {
                            if let existingBox = maxWordBoxes[assetWord], existingBox.box.width * existingBox.box.height < currentBoxArea {
                                maxWordBoxes[assetWord] = (observation.boundingBox, assetDetails.meaning)
                            } else if maxWordBoxes[assetWord] == nil {
                                maxWordBoxes[assetWord] = (observation.boundingBox, assetDetails.meaning)
                            }
                        }
                    }
                }
            }

            self.removeAllWordLabels()
            for (word, details) in maxWordBoxes {
                let wordRect = self.transformBoundingBox(details.box)
                self.createHighlightedWordLabel(word: word, frame: wordRect)
            }
        }
    }




    func transformBoundingBox(_ box: CGRect) -> CGRect {
        let screenSize = sceneView.bounds.size
        let scaleX = screenSize.width
        let scaleY = screenSize.height
        let x = box.minX * scaleX
        let y = (1 - box.minY - box.height) * scaleY
        let width = box.width * scaleX
        let height = box.height * scaleY
        return CGRect(x: x, y: y, width: width, height: height)
    }


    private var wordLabels: [String: UILabel] = [:]

        func createHighlightedWordLabel(word: String, frame: CGRect) {
            let labelWidth = max(frame.width, word.widthOfString(usingFont: UIFont.systemFont(ofSize: 14)) + 20)

            let adjustedFrame = CGRect(x: frame.minX, y: frame.minY, width: labelWidth, height: frame.height)

            if let existingLabel = wordLabels[word] {
                existingLabel.frame = adjustedFrame
            } else {
                let label = UILabel(frame: adjustedFrame)
                label.backgroundColor = UIColor.red.withAlphaComponent(0.3)
                label.text = word
                label.textAlignment = .center
                label.font = UIFont.systemFont(ofSize: 14)
                label.isUserInteractionEnabled = true
                let tapGesture = UITapGestureRecognizer(target: self, action: #selector(wordLabelTapped(_:)))
                label.addGestureRecognizer(tapGesture)
                view.addSubview(label)
                wordLabels[word] = label
            }
        }
    
        func removeAllWordLabels() {
            wordLabels.forEach { $0.value.removeFromSuperview() }
            wordLabels.removeAll()
        }


    @objc func wordLabelTapped(_ recognizer: UITapGestureRecognizer) {
        guard let label = recognizer.view as? UILabel else { return }
        let word = label.text ?? ""
        lastDetectedWord = word

        displayModelAndMeaning(for: word)
        playButton.isHidden = false
        meaningLabel.text = wordAssets[word]?.meaning
        meaningLabel.isHidden = false
    }



    
    func displayModelAndMeaning(for word: String) {
        removeAllModels()
        
        guard let asset = wordAssets[word], let modelScene = SCNScene(named: asset.modelName) else {
            print("Failed to load the model for \(word)")
            return
        }
        
        let node = modelScene.rootNode.clone()
        node.name = word
        node.position = SCNVector3(0, -0.5, -0.5)
        node.scale = SCNVector3(0.001, 0.001, 0.001)

        if asset.hasAnimation {
            if let animationPlayer = node.animationPlayer(forKey: word) {
                animationPlayer.play()
            }
        }
        
        sceneView.scene.rootNode.addChildNode(node)
        currentNodes.append(node)
        
        playButton.isHidden = false
        meaningLabel.text = asset.meaning
        meaningLabel.isHidden = false
    }

    
    func removeAllModels() {
        currentNodes.forEach { $0.removeFromParentNode() }
        currentNodes.removeAll()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("ARセッションでエラーが発生しました: \(error.localizedDescription)")
    }

    func sessionWasInterrupted(_ session: ARSession) {
        print("ARセッションが中断されました")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        print("ARセッションが再開されました")
    }
}
