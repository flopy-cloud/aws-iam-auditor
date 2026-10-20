# # Auditor de seguridad IAM con Terraform

## Objetivo
Revisar automáticamente, una vez por semana, la seguridad de las cuentas de IAM: usuarios con acceso a la consola sin MFA y access keys que llevan demasiado tiempo sin rotarse. El resultado se guarda como reporte y llega por email.

## Arquitectura
- **EventBridge:** dispara la auditoría todos los lunes a las 09:00 (hora de Argentina).
- **Lambda (Python 3.13):** genera el *credential report* de IAM, lo analiza y arma el reporte.
- **S3:** guarda cada reporte como JSON (`reportes/AAAA-MM-DD.json`). El bucket es privado, con el acceso público bloqueado.
- **SNS:** envía el resumen por email.
- **IAM:** rol con permisos mínimos. Solo puede generar y leer el credential report, escribir en ese bucket y publicar en ese tema de SNS.

Toda la infraestructura está definida con **Terraform** en la región `us-east-1`.

## Qué revisa
- Usuarios con acceso a la consola sin MFA.
- Access keys activas con más de 90 días sin rotarse (configurable con una variable).
- Cuenta root sin MFA o con access keys activas.

## Cómo usarlo
Crear un archivo `terraform.tfvars` con el email que recibirá los reportes (no se sube al repo):

```hcl
email = "tu-email@ejemplo.com"
```

Desplegar:

```bash
terraform init
terraform plan
terraform apply
```

Confirmar la suscripción de SNS desde el email que llega. Para probarlo sin esperar al lunes:

```bash
aws lambda invoke --function-name iam-auditor \
  --cli-binary-format raw-in-base64-out \
  --payload '{}' salida.json
```

Para eliminar todo:

```bash
terraform destroy
```

## Resultados

### Despliegue con Terraform
<img width="508" height="42" alt="Captura de pantalla de 2026-10-20 18-10-34" src="https://github.com/user-attachments/assets/7722407d-cf59-4048-b2e4-552c169f3adb" />


### Reporte guardado en S3
<img width="1454" height="73" alt="Captura de pantalla de 2026-10-20 18-18-13" src="https://github.com/user-attachments/assets/6dc9bc02-2b7d-4d72-aecd-3f39535ba3a7" />


### Contenido del reporte
<img width="1065" height="84" alt="WA_1792533086421" src="https://github.com/user-attachments/assets/5c1b4e2b-f6a2-4f11-9b96-3beb35720dd2" />


### Resumen recibido por email
<img width="1080" height="930" alt="photo_5098545013137804746_y" src="https://github.com/user-attachments/assets/33b5d50d-e680-40e4-a9b7-56ea87947962" />


## Qué aprendí
- El *credential report* de IAM da en un solo archivo el estado de MFA y de las access keys de todos los usuarios, sin tener que consultarlos uno por uno.
- Con permisos mínimos en el rol, la Lambda solo puede hacer lo que necesita.
- Un bucket de S3 privado, con el acceso público bloqueado, es lo correcto para guardar reportes de seguridad.
- La suscripción de SNS por email no funciona hasta que se confirma.

## Costo
Prácticamente cero. Lambda, SNS y el credential report entran en el free tier, y S3 cuesta centavos por unos pocos archivos pequeños. Destruí la infraestructura después de las pruebas.aws-iam-auditor
