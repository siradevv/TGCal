import SwiftUI
import PhotosUI

struct ProfileView: View {
    @ObservedObject private var supabase = SupabaseService.shared

    @State private var isEditing = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Edit form state
    @State private var editName = ""
    @State private var editRank: CrewRank = .cabin
    @State private var editBatch = ""

    // Avatar
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cropperImage: IdentifiableImage?
    @State private var avatarImage: UIImage?
    @State private var isUploadingAvatar = false

    var body: some View {
        ZStack {
            TGBackgroundView()

            ScrollView {
                VStack(spacing: 20) {
                    avatarSection
                    nameSection

                    if isEditing {
                        editFormSection
                    } else {
                        infoCardSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        cancelEditing()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await saveProfile() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        startEditing()
                    }
                }
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task { await loadSelectedPhoto(newItem) }
        }
        .fullScreenCover(item: $cropperImage) { item in
            CircularCropView(image: item.image) { cropped in
                avatarImage = cropped
                cropperImage = nil
            } onCancel: {
                cropperImage = nil
            }
        }
    }

    // MARK: - Avatar Section

    private var avatarSection: some View {
        Group {
            if isEditing {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    avatarContent
                        .overlay(alignment: .bottom) {
                            Image(systemName: "camera.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(TGTheme.indigo))
                                .offset(y: 6)
                        }
                }
                .buttonStyle(.plain)
            } else {
                avatarContent
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var avatarContent: some View {
        Group {
            if isUploadingAvatar {
                ZStack {
                    Circle()
                        .fill(TGTheme.indigo.opacity(0.15))
                        .frame(width: 100, height: 100)
                    ProgressView()
                }
            } else if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(TGTheme.cardStroke, lineWidth: 2))
            } else if let urlString = supabase.currentUser?.avatarUrl,
                      let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(TGTheme.cardStroke, lineWidth: 2))
                    default:
                        initialsAvatar
                    }
                }
            } else {
                initialsAvatar
            }
        }
    }

    private var initialsAvatar: some View {
        ZStack {
            Circle()
                .fill(TGTheme.indigo.opacity(0.15))
                .frame(width: 100, height: 100)
            Text(initials)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(TGTheme.indigo)
        }
    }

    private var initials: String {
        let name = supabase.currentUser?.displayName ?? ""
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(spacing: 6) {
            Text(supabase.currentUser?.displayName ?? "Crew Member")
                .font(.title2.weight(.semibold))

            Text(supabase.currentUser?.crewRank.displayName ?? "Cabin Crew")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(TGTheme.indigo)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(TGTheme.indigo.opacity(0.14)))

            if let batch = supabase.currentUser?.batch, !batch.isEmpty {
                Text("Batch \(batch)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Info Card (View Mode)

    private var infoCardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let email = userEmail {
                infoRow(icon: "envelope.fill", label: "Email", value: email)
                Divider().padding(.leading, 40)
            }

            if let joinDate = supabase.currentUser?.createdAt {
                infoRow(icon: "calendar", label: "Joined", value: joinDate.formattedJoinDate)
            }
        }
        .tgFrostedCard(verticalPadding: 4)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(TGTheme.indigo)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
            }

            Spacer()
        }
        .padding(.vertical, 10)
    }

    // MARK: - Edit Form

    private var editFormSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Display Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Your name", text: $editName)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(TGTheme.insetFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(TGTheme.insetStroke, lineWidth: 1)
                            )
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Crew Rank")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Rank", selection: $editRank) {
                    ForEach(CrewRank.allCases) { rank in
                        Text(rank.displayName).tag(rank)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Training Batch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. 52", text: $editBatch)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(TGTheme.insetFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(TGTheme.insetStroke, lineWidth: 1)
                            )
                    )
            }
        }
        .tgFrostedCard(verticalPadding: 14)
    }

    // MARK: - Helpers

    private var userEmail: String? {
        try? supabase.client.auth.currentSession?.user.email
    }

    private func startEditing() {
        if let profile = supabase.currentUser {
            editName = profile.displayName
            editRank = profile.crewRank
            editBatch = profile.batch ?? ""
        }
        avatarImage = nil
        cropperImage = nil
        selectedPhoto = nil
        errorMessage = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
        }
    }

    private func cancelEditing() {
        avatarImage = nil
        cropperImage = nil
        selectedPhoto = nil
        errorMessage = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = false
        }
    }

    private func saveProfile() async {
        let name = editName.trimmingCharacters(in: .whitespaces)
        guard name.count >= 2 else {
            errorMessage = "Name must be at least 2 characters"
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if let avatarImage {
                isUploadingAvatar = true
                defer { isUploadingAvatar = false }

                if let data = resizedAvatarData(avatarImage) {
                    do {
                        _ = try await supabase.uploadAvatar(imageData: data)
                    } catch {
                        errorMessage = "Avatar upload failed: \(error.localizedDescription)"
                        return
                    }
                }
            }

            let batch = editBatch.trimmingCharacters(in: .whitespaces)
            try await supabase.updateProfile(
                displayName: name,
                crewRank: editRank,
                batch: batch.isEmpty ? nil : batch
            )

            withAnimation(.easeInOut(duration: 0.2)) {
                isEditing = false
            }
        } catch {
            errorMessage = "Profile update failed: \(error.localizedDescription)"
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        // Load on background thread to avoid freezing
        let loadedImage: UIImage? = await Task.detached {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
            // Downsample large images to prevent memory issues
            let maxDimension: CGFloat = 2000
            guard let uiImage = UIImage(data: data) else { return nil }
            let size = uiImage.size
            if size.width <= maxDimension && size.height <= maxDimension {
                return uiImage
            }
            let scale = min(maxDimension / size.width, maxDimension / size.height)
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            return renderer.image { _ in
                uiImage.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }.value

        guard let loadedImage else { return }
        cropperImage = IdentifiableImage(image: loadedImage)
    }

    private func resizedAvatarData(_ image: UIImage) -> Data? {
        let maxSize: CGFloat = 400
        let size = image.size

        let scale: CGFloat
        if size.width > maxSize || size.height > maxSize {
            scale = min(maxSize / size.width, maxSize / size.height)
        } else {
            scale = 1.0
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized.jpegData(compressionQuality: 0.7)
    }
}

// MARK: - Circular Crop View

private struct CircularCropView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var circleSize: CGFloat = 300
    @State private var viewSize: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height) * 0.82

                ZStack {
                    // Zoomable/pannable image
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        let newScale = lastScale * value.magnification
                                        scale = max(1.0, min(newScale, 5.0))
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                        )

                    // Dark overlay with circular cutout
                    CircularMask(circleSize: size)
                        .fill(style: FillStyle(eoFill: true))
                        .foregroundStyle(.black.opacity(0.6))
                        .allowsHitTesting(false)

                    // Circle border
                    Circle()
                        .stroke(.white.opacity(0.5), lineWidth: 1)
                        .frame(width: size, height: size)
                        .allowsHitTesting(false)
                }
                .onAppear {
                    circleSize = size
                    viewSize = geo.size
                }
            }

            // Controls at top and bottom, in safe area
            VStack {
                Spacer()

                Text("Pinch to zoom, drag to move")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 16)

                HStack {
                    Button {
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        let cropped = renderCroppedImage()
                        onCrop(cropped)
                    } label: {
                        Text("Choose")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(TGTheme.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }

    /// Renders the exact visible content inside the circle to a square UIImage.
    private func renderCroppedImage() -> UIImage {
        let outputSize: CGFloat = 800
        let imageSize = image.size

        // How the image is rendered in the view (scaledToFill)
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        let renderedSize: CGSize
        if imageAspect > viewAspect {
            renderedSize = CGSize(width: viewSize.height * imageAspect, height: viewSize.height)
        } else {
            renderedSize = CGSize(width: viewSize.width, height: viewSize.width / imageAspect)
        }

        // After user zoom
        let scaledW = renderedSize.width * scale
        let scaledH = renderedSize.height * scale

        // Image top-left in view coordinates
        let imageOriginX = (viewSize.width - scaledW) / 2 + offset.width
        let imageOriginY = (viewSize.height - scaledH) / 2 + offset.height

        // Circle center in view coordinates
        let circleCenterX = viewSize.width / 2
        let circleCenterY = viewSize.height / 2

        // Circle top-left relative to image, in pixel-space
        let pixelsPerPointX = imageSize.width / scaledW
        let pixelsPerPointY = imageSize.height / scaledH

        let cropOriginX = (circleCenterX - circleSize / 2 - imageOriginX) * pixelsPerPointX
        let cropOriginY = (circleCenterY - circleSize / 2 - imageOriginY) * pixelsPerPointY
        let cropSize = circleSize * pixelsPerPointX

        // Clamp to image bounds
        let rect = CGRect(
            x: max(0, cropOriginX),
            y: max(0, cropOriginY),
            width: min(imageSize.width - max(0, cropOriginX), cropSize),
            height: min(imageSize.height - max(0, cropOriginY), cropSize)
        )

        // Render to a clean square image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize))
        return renderer.image { ctx in
            // Draw the cropped region scaled to fill the output square
            image.draw(in: CGRect(
                x: -rect.origin.x * (outputSize / rect.width),
                y: -rect.origin.y * (outputSize / rect.height),
                width: imageSize.width * (outputSize / rect.width),
                height: imageSize.height * (outputSize / rect.height)
            ))
        }
    }
}

private struct CircularMask: Shape {
    let circleSize: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addEllipse(in: CGRect(
            x: rect.midX - circleSize / 2,
            y: rect.midY - circleSize / 2,
            width: circleSize,
            height: circleSize
        ))
        return path
    }
}

private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private extension Date {
    var formattedJoinDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: self)
    }
}
