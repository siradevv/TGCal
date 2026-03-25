-- Add photo_url column to layover_tips
ALTER TABLE layover_tips ADD COLUMN IF NOT EXISTS photo_url TEXT;

-- Create layover_photos storage bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('layover_photos', 'layover_photos', true)
ON CONFLICT DO NOTHING;

-- Authenticated users can upload photos (path: {userId}/{photoId}.jpg)
CREATE POLICY "layover_photos_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'layover_photos'
    AND auth.uid()::text = split_part(name, '/', 1)
);

CREATE POLICY "layover_photos_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'layover_photos'
    AND auth.uid()::text = split_part(name, '/', 1)
);

CREATE POLICY "layover_photos_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'layover_photos'
    AND auth.uid()::text = split_part(name, '/', 1)
);

-- Anyone can view layover photos
CREATE POLICY "layover_photos_select"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'layover_photos');
