class DiagnosticScreen
         extends StatelessWidget {
       const DiagnosticScreen({
         super.key,
       });
     
       @override
       Widget build(BuildContext context) {
         return Scaffold(
           appBar: AppBar(
             title:
                 const Text('Diagnostics'),
           ),
           body: ListView(
             children: const [
               ListTile(
                 leading:
                     Icon(Icons.check),
                 title:
                     Text('Firebase'),
               ),
               ListTile(
                 leading:
                     Icon(Icons.check),
                 title:
                     Text('Firestore'),
               ),
               ListTile(
                 leading:
                     Icon(Icons.check),
                 title:
                     Text('Auth'),
               ),
               ListTile(
                 leading:
                     Icon(Icons.check),
                 title:
                     Text('Maps'),
               ),
               ListTile(
                 leading:
                     Icon(Icons.check),
                title:
                     Text('Location'),
               ),
             ],
           ),
         );
       }
     }
