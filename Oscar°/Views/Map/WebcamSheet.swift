import SwiftUI
import UIKit

/// One webcam tapped on the map: its latest picture to pinch and zoom, when it was taken,
/// and the way to windy.com. Loads the picture when shown, never in the background
/// (Windy's terms forbid scanning, and image URLs expire after 10 min).
struct WebcamSheet: View {
    static let previewSize = CGSize(width: 400, height: 224)

    let webcam: Components.Schemas.Webcam
    @State private var photo: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let photo {
                    ZoomableImage(image: photo)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .aspectRatio(Self.previewSize, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 12))
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: webcam.title))
            .accessibilityAddTraits(.isImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: webcam.title)
                    .font(.headline)
                Text("Aufgenommen \(webcam.updated_at.formatted(.relative(presentation: .named)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                if let player = webcam.player_url.flatMap(URL.init(string:)) {
                    Link("Zeitraffer von heute", destination: player)
                }
                if let detail = URL(string: webcam.detail_url) {
                    Link("Auf windy.com ansehen", destination: detail)
                }
            }
            .font(.body.weight(.semibold))
            Spacer(minLength: 0)
            WebcamCredit()
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            guard let url = URL(string: webcam.preview_url) else { return }
            let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)
            guard let data = try? await URLSession.shared.data(for: request).0 else { return }
            photo = UIImage(data: data)
        }
    }
}

/// Pinch or double-tap to zoom, drag to pan.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 2.5
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        let imageView = context.coordinator.imageView
        imageView.contentMode = .scaleAspectFill
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView.image = image
        if scrollView.zoomScale == 1 {
            context.coordinator.imageView.frame = scrollView.bounds
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let width = scrollView.bounds.width / 2.5
                let height = scrollView.bounds.height / 2.5
                let rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}

/// The acknowledgment Windy's terms require next to every webcam, in their wording and with
/// both links, so it stays English in every language.
struct WebcamCredit: View {
    private static let text = (try? AttributedString(markdown:
        "Webcams provided by [windy.com](https://www.windy.com) - [add new webcam](https://www.windy.com/webcams/add)"))
        ?? AttributedString("Webcams provided by windy.com")

    var body: some View {
        Text(Self.text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
