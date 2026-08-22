import 'package:flutter/material.dart'    
      class StartupFailureScreen
         extends StatelessWidget {
       final String error;
     
       const StartupFailureScreen({
         super.key,
         required this.error,
       });
     
       @override
       Widget build(BuildContext context) {
         return Scaffold(
           body: SafeArea(
             child: Padding(
               padding:
                   const EdgeInsets.all(24),
              child: Column(
                 mainAxisAlignment:
                     MainAxisAlignment.center,
                 children: [
                   const Icon(
                     Icons.error_outline,
                     color: Colors.red,
                     size: 80,
                   ),
     
                   const SizedBox(height: 20),
     
                   const Text(
                     'EVPair could not start',
                     style: TextStyle(
                       fontSize: 24,
                       fontWeight:
                           FontWeight.bold,
                     ),
                   ),
     
                   const SizedBox(height: 12),
     
                   Text(
                     error,
                     textAlign:
                         TextAlign.center,
                   ),
     
                   const SizedBox(height: 24),
     
                   ElevatedButton(
                     onPressed: () {},
                     child: const Text(
                       'Send Report',
                   ),
                   ),
                 ],
               ),
             ),
           ),
         );
       }
     }
