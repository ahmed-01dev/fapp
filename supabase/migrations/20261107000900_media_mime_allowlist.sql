-- Expand the private media bucket to common document formats.
update storage.buckets
set public = false,
    file_size_limit = 52428800,
    allowed_mime_types = array[
      'image/jpeg','image/png','image/webp','image/gif',
      'video/mp4','video/webm',
      'audio/aac','audio/mpeg','audio/ogg','audio/mp4','audio/wav',
      'application/pdf','text/plain','text/csv','application/zip',
      'application/msword','application/vnd.ms-excel','application/vnd.ms-powerpoint',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation'
    ]
where id = 'chat-media';
